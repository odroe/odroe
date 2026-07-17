import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;

/// The severity of a file-route diagnostic.
enum FileRouteDiagnosticSeverity {
  /// Compilation cannot produce a valid route tree.
  error,

  /// Compilation succeeded but the declaration deserves attention.
  warning,
}

/// A source-oriented file-route diagnostic.
final class FileRouteDiagnostic {
  /// Creates a diagnostic.
  const FileRouteDiagnostic({
    required this.severity,
    required this.path,
    required this.message,
  });

  /// Diagnostic severity.
  final FileRouteDiagnosticSeverity severity;

  /// Project-relative source path.
  final String path;

  /// Human-readable problem description.
  final String message;

  @override
  String toString() => '${severity.name}: $path: $message';
}

/// The immutable result of compiling a routes directory.
final class FileRouteOutput {
  /// Creates compiler output.
  const FileRouteOutput({
    required this.source,
    required this.diagnostics,
    required this.routeCount,
    this.changed = false,
  });

  /// Generated Dart source.
  final String source;

  /// Diagnostics collected without throwing.
  final List<FileRouteDiagnostic> diagnostics;

  /// Number of route nodes in the generated tree.
  final int routeCount;

  /// Whether [FileRouteCompiler.write] changed the output file.
  final bool changed;

  /// Whether any fatal diagnostic was produced.
  bool get hasErrors => diagnostics.any(
    (diagnostic) => diagnostic.severity == FileRouteDiagnosticSeverity.error,
  );
}

/// Thrown when a file-route tree cannot be generated safely.
final class FileRouteCompilationException implements Exception {
  /// Creates a compilation failure.
  const FileRouteCompilationException(this.diagnostics);

  /// Fatal and non-fatal diagnostics from the attempted compilation.
  final List<FileRouteDiagnostic> diagnostics;

  @override
  String toString() => diagnostics.join('\n');
}

/// Compiles `lib/routes/` into one ordinary runtime route tree.
final class FileRouteCompiler {
  /// Creates a compiler rooted at a Dart or Flutter application.
  FileRouteCompiler({
    required Directory projectRoot,
    String routesPath = 'lib/routes',
    String outputPath = 'lib/routes.dart',
  }) : projectRoot = projectRoot.absolute,
       routesDirectory = Directory(
         p.join(projectRoot.absolute.path, routesPath),
       ),
       outputFile = File(p.join(projectRoot.absolute.path, outputPath));

  /// Application package root.
  final Directory projectRoot;

  /// Source routes directory.
  final Directory routesDirectory;

  /// Generated route-tree file.
  final File outputFile;

  /// Compiles routes without changing the file system.
  FileRouteOutput compile() {
    final diagnostics = <FileRouteDiagnostic>[];
    if (!routesDirectory.existsSync()) {
      diagnostics.add(
        FileRouteDiagnostic(
          severity: FileRouteDiagnosticSeverity.error,
          path: _relative(routesDirectory.path),
          message: 'Routes directory does not exist.',
        ),
      );
      return FileRouteOutput(
        source: '',
        diagnostics: List<FileRouteDiagnostic>.unmodifiable(diagnostics),
        routeCount: 0,
      );
    }

    final root = _scan(
      routesDirectory,
      const <String>[],
      diagnostics,
      isRoot: true,
    );
    _validateTree(root, diagnostics, <_RouteField>[]);
    final nodes = <_RouteNode>[];
    _flatten(root, nodes);
    _validateGeneratedNames(nodes, diagnostics);
    var source = '';
    if (!diagnostics.any(
      (diagnostic) => diagnostic.severity == FileRouteDiagnosticSeverity.error,
    )) {
      try {
        source = _generate(root, nodes);
      } on FormatterException catch (error) {
        _error(
          diagnostics,
          outputFile.path,
          'Generated route source is invalid: $error',
        );
      }
    }
    return FileRouteOutput(
      source: source,
      diagnostics: List<FileRouteDiagnostic>.unmodifiable(diagnostics),
      routeCount: nodes.length,
    );
  }

  /// Compiles routes and writes the generated file atomically.
  FileRouteOutput write() {
    final output = compile();
    if (output.hasErrors) {
      throw FileRouteCompilationException(output.diagnostics);
    }
    outputFile.parent.createSync(recursive: true);
    if (outputFile.existsSync() &&
        outputFile.readAsStringSync() == output.source) {
      return output;
    }
    final temporary = File('${outputFile.path}.tmp');
    try {
      temporary.writeAsStringSync(output.source);
      temporary.renameSync(outputFile.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
    return FileRouteOutput(
      source: output.source,
      diagnostics: output.diagnostics,
      routeCount: output.routeCount,
      changed: true,
    );
  }

  _RouteNode _scan(
    Directory directory,
    List<String> segments,
    List<FileRouteDiagnostic> diagnostics, {
    required bool isRoot,
  }) {
    final routeFile = File(p.join(directory.path, 'route.dart'));
    final pageFile = File(p.join(directory.path, 'page.dart'));
    final shellFile = File(p.join(directory.path, 'shell.dart'));
    final serverFile = File(p.join(directory.path, 'server.dart'));
    final node = _RouteNode(
      directory: directory,
      segments: segments,
      path: isRoot ? '/' : _segmentPath(segments.last),
      routeFile: routeFile.existsSync() ? routeFile : null,
      pageFile: pageFile.existsSync() ? pageFile : null,
      shellFile: shellFile.existsSync() ? shellFile : null,
      serverFile: serverFile.existsSync() ? serverFile : null,
    );

    if (node.routeFile case final file?) {
      node.contract = _parseContract(file, diagnostics);
    }
    if (node.pageFile case final file?) {
      _requireRouteVariable(file, diagnostics);
    }
    if (node.shellFile case final file?) {
      _requireRouteVariable(file, diagnostics);
    }
    if (node.serverFile case final file?) {
      _requireRouteVariable(file, diagnostics);
      if (node.routeFile == null) {
        _error(
          diagnostics,
          file.path,
          'server.dart requires route.dart as its shared typed contract.',
        );
      }
    }

    final childDirectories =
        directory
            .listSync(followLinks: false)
            .whereType<Directory>()
            .where((child) => !p.basename(child.path).startsWith('.'))
            .toList()
          ..sort(
            (left, right) =>
                p.basename(left.path).compareTo(p.basename(right.path)),
          );
    for (final child in childDirectories) {
      final name = p.basename(child.path);
      if (!_validDirectoryName(name)) {
        _error(
          diagnostics,
          child.path,
          'Invalid route directory "$name". Use a static segment, [name], '
          '[...name], or (group).',
        );
        continue;
      }
      final childNode = _scan(
        child,
        <String>[...segments, name],
        diagnostics,
        isRoot: false,
      );
      if (!childNode.hasContent) continue;
      childNode.parent = node;
      node.children.add(childNode);
    }
    return node;
  }

  _RouteContract _parseContract(
    File file,
    List<FileRouteDiagnostic> diagnostics,
  ) {
    final content = file.readAsStringSync();
    final result = parseString(
      content: content,
      path: file.path,
      throwIfDiagnostics: false,
    );
    for (final error in result.errors) {
      _error(diagnostics, file.path, error.message);
    }

    _RecordContract? params;
    _RecordContract? search;
    VariableDeclaration? routeVariable;
    for (final declaration in result.unit.declarations) {
      if (declaration is TopLevelVariableDeclaration) {
        for (final variable in declaration.variables.variables) {
          if (variable.name.lexeme == 'route') routeVariable = variable;
        }
      }
      if (declaration is! GenericTypeAlias) continue;
      final name = declaration.name.lexeme;
      if (name != 'Params' && name != 'Search') continue;
      final type = declaration.type;
      if (type is! RecordTypeAnnotation ||
          type.positionalFields.isNotEmpty ||
          type.namedFields == null) {
        _error(
          diagnostics,
          file.path,
          '$name must be a record typedef with named fields.',
        );
        continue;
      }
      final record = _RecordContract(
        name: name,
        fields: type.namedFields!.fields
            .map(
              (field) => _RouteField(
                name: field.name.lexeme,
                type: field.type.toSource(),
              ),
            )
            .toList(growable: false),
      );
      if (name == 'Params') {
        params = record;
      } else {
        search = record;
      }
    }

    if (routeVariable == null) {
      _error(
        diagnostics,
        file.path,
        'File must export a top-level variable named route.',
      );
    }
    final initializer = routeVariable?.initializer;
    final isAppRoute =
        initializer != null &&
        RegExp(
          r'^(?:[A-Za-z_][A-Za-z0-9_]*\.)?AppRoute\s*<',
        ).hasMatch(initializer.toSource());
    if (routeVariable != null && !isAppRoute) {
      _error(
        diagnostics,
        file.path,
        'route.dart must initialize route with AppRoute<Params, Search, Data>.',
      );
    }
    final typeArguments = switch (initializer) {
      InstanceCreationExpression() =>
        initializer.constructorName.type.typeArguments,
      MethodInvocation() => initializer.typeArguments,
      _ => null,
    };
    final arguments = typeArguments?.arguments;
    if (isAppRoute && arguments != null) {
      if (arguments.length != 3) {
        _error(
          diagnostics,
          file.path,
          'AppRoute must declare params, search, and data type arguments.',
        );
      } else {
        final expectedParams = params == null ? 'NoParams' : 'Params';
        final expectedSearch = search == null ? 'NoSearch' : 'Search';
        if (!_isNamedType(arguments[0].toSource(), expectedParams)) {
          _error(
            diagnostics,
            file.path,
            'AppRoute params type must be $expectedParams.',
          );
        }
        if (!_isNamedType(arguments[1].toSource(), expectedSearch)) {
          _error(
            diagnostics,
            file.path,
            'AppRoute search type must be $expectedSearch.',
          );
        }
      }
    }
    final argumentList = switch (initializer) {
      InstanceCreationExpression() => initializer.argumentList,
      MethodInvocation() => initializer.argumentList,
      _ => null,
    };
    final argumentNames = argumentList != null
        ? argumentList.arguments
              .whereType<NamedExpression>()
              .map((argument) => argument.name.label.name)
              .toSet()
        : const <String>{};
    final declaresParams = argumentNames.contains('params');
    final declaresSearch = argumentNames.contains('search');
    if (declaresParams && params == null) {
      _error(
        diagnostics,
        file.path,
        'A route with params must declare typedef Params.',
      );
    }
    if (declaresSearch && search == null) {
      _error(
        diagnostics,
        file.path,
        'A route with search must declare typedef Search.',
      );
    }

    final paramsSchema = RegExp(
      r'PathParams\s*<\s*Params\s*>\s*\.schema\s*\(',
    ).hasMatch(content);
    final searchSchema = RegExp(
      r'SearchParams\s*<\s*Search\s*>\s*\.schema\s*\(',
    ).hasMatch(content);
    if (paramsSchema && params == null) {
      _error(
        diagnostics,
        file.path,
        'PathParams<Params>.schema() requires typedef Params.',
      );
    }
    if (searchSchema && search == null) {
      _error(
        diagnostics,
        file.path,
        'SearchParams<Search>.schema() requires typedef Search.',
      );
    }
    return _RouteContract(
      params: params,
      search: search,
      paramsSchema: paramsSchema,
      searchSchema: searchSchema,
      declaresParams: declaresParams,
      declaresSearch: declaresSearch,
    );
  }

  void _requireRouteVariable(File file, List<FileRouteDiagnostic> diagnostics) {
    final result = parseString(
      content: file.readAsStringSync(),
      path: file.path,
      throwIfDiagnostics: false,
    );
    if (result.errors.isNotEmpty) {
      for (final error in result.errors) {
        _error(diagnostics, file.path, error.message);
      }
      return;
    }
    final exportsRoute = result.unit.declarations
        .whereType<TopLevelVariableDeclaration>()
        .expand((declaration) => declaration.variables.variables)
        .any((variable) => variable.name.lexeme == 'route');
    if (!exportsRoute) {
      _error(
        diagnostics,
        file.path,
        'File must export a top-level variable named route.',
      );
    }
  }

  void _validateTree(
    _RouteNode node,
    List<FileRouteDiagnostic> diagnostics,
    List<_RouteField> inheritedParams,
  ) {
    final names = _dynamicNames(node.path);
    final params = node.contract?.params;
    if (names.isNotEmpty && node.routeFile == null) {
      _error(
        diagnostics,
        node.directory.path,
        'Dynamic route ${node.path} requires route.dart with typedef Params.',
      );
    }
    if (names.isNotEmpty && params == null && node.routeFile != null) {
      _error(
        diagnostics,
        node.routeFile!.path,
        'Dynamic route ${node.path} requires typedef Params.',
      );
    }
    if (names.isNotEmpty && params != null) {
      final fieldNames = params.fields.map((field) => field.name).toSet();
      if (fieldNames.length != names.length || !fieldNames.containsAll(names)) {
        _error(
          diagnostics,
          node.routeFile!.path,
          'Params fields $fieldNames must exactly match path fields $names.',
        );
      }
    }
    if (names.isEmpty && params != null && params.fields.isNotEmpty) {
      _error(
        diagnostics,
        node.routeFile!.path,
        'typedef Params is only valid in a dynamic route directory.',
      );
    }
    if (params != null && !(node.contract?.declaresParams ?? false)) {
      _error(
        diagnostics,
        node.routeFile!.path,
        'typedef Params requires a params argument on AppRoute.',
      );
    }
    if (node.contract?.search != null &&
        !(node.contract?.declaresSearch ?? false)) {
      _error(
        diagnostics,
        node.routeFile!.path,
        'typedef Search requires a search argument on AppRoute.',
      );
    }

    final contract = node.contract;
    if (contract?.paramsSchema ?? false) {
      if (!_schemaFieldsSupported(contract!.params!.fields, path: true)) {
        _error(
          diagnostics,
          node.routeFile!.path,
          'PathParams.schema() supports non-nullable String, int, double, '
          'bool, and List<String>. Use PathParams.codec() for custom types.',
        );
      }
      if (names.isNotEmpty && contract.params!.fields.length == 1) {
        final type = contract.params!.fields.single.type;
        if (_isRestPath(node.path) && type != 'List<String>') {
          _error(
            diagnostics,
            node.routeFile!.path,
            'A catch-all route requires a List<String> schema field.',
          );
        }
        if (!_isRestPath(node.path) && type == 'List<String>') {
          _error(
            diagnostics,
            node.routeFile!.path,
            'List<String> is only valid for a catch-all route.',
          );
        }
      }
    }
    if (contract?.searchSchema ?? false) {
      if (!_schemaFieldsSupported(contract!.search!.fields, path: false)) {
        _error(
          diagnostics,
          node.routeFile!.path,
          'SearchParams.schema() supports String, int, double, bool, and '
          'List<String>. Use SearchParams.codec() for custom types.',
        );
      }
    }

    final nextParams = <_RouteField>[...inheritedParams];
    for (final field in params?.fields ?? const <_RouteField>[]) {
      field.owner = node;
      if (nextParams.any((existing) => existing.name == field.name)) {
        _error(
          diagnostics,
          node.routeFile!.path,
          'Path parameter "${field.name}" already exists in an ancestor route.',
        );
      }
      nextParams.add(field);
    }

    if (_isRestPath(node.path) && node.children.isNotEmpty) {
      _error(
        diagnostics,
        node.directory.path,
        'A catch-all route cannot have child routes.',
      );
    }

    final childPaths = <String, _RouteNode>{};
    final childMembers = <String, _RouteNode>{};
    for (final child in node.children) {
      final samePath = childPaths[child.path];
      final bothNonTerminalGroups =
          child.path.isEmpty &&
          samePath != null &&
          child.pageFile == null &&
          samePath.pageFile == null;
      if (samePath != null && !bothNonTerminalGroups) {
        _error(
          diagnostics,
          child.directory.path,
          'Sibling route path "${child.path}" is duplicated.',
        );
      } else {
        childPaths[child.path] = child;
      }
      final sameMember = childMembers[child.memberName];
      if (sameMember != null) {
        _error(
          diagnostics,
          child.directory.path,
          'Generated route member "${child.memberName}" conflicts with '
          '${_relative(sameMember.directory.path)}.',
        );
      } else {
        childMembers[child.memberName] = child;
      }
      _validateTree(child, diagnostics, nextParams);
    }
  }

  void _validateGeneratedNames(
    List<_RouteNode> nodes,
    List<FileRouteDiagnostic> diagnostics,
  ) {
    final keys = <String, _RouteNode>{};
    final terminalPatterns = <String, _RouteNode>{};
    for (final node in nodes) {
      final existing = keys[node.key];
      if (existing == null) {
        keys[node.key] = node;
      } else {
        _error(
          diagnostics,
          node.directory.path,
          'Generated route name "${node.key}" conflicts with '
          '${_relative(existing.directory.path)}.',
        );
      }

      if (node.pageFile == null) continue;
      final pattern = node.effectivePattern;
      final samePattern = terminalPatterns[pattern];
      if (samePattern == null) {
        terminalPatterns[pattern] = node;
        continue;
      }
      _error(
        diagnostics,
        node.directory.path,
        'Terminal route pattern "$pattern" conflicts with '
        '${_relative(samePattern.directory.path)}.',
      );
    }
  }

  String _generate(_RouteNode root, List<_RouteNode> nodes) {
    final buffer = StringBuffer()
      ..writeln('// Generated by Odroe. Do not edit.')
      ..writeln('// ignore_for_file: type=lint')
      ..writeln()
      ..writeln("import 'package:odroe/router.dart';");
    for (final node in nodes) {
      for (final entry in node.imports(outputFile.parent.path)) {
        buffer.writeln("import '${entry.uri}' as ${entry.alias};");
      }
    }
    buffer.writeln();

    for (final node in nodes.reversed) {
      _writeCompiledRoute(buffer, node);
    }
    buffer
      ..writeln(
        'final List<AnyAppRoute> routeTree = <AnyAppRoute>[_routeRoot];',
      )
      ..writeln()
      ..writeln('const routes = AppRoutes();')
      ..writeln();
    for (final node in nodes) {
      _writeFacade(buffer, node);
    }
    return DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
    ).format(buffer.toString());
  }

  void _writeCompiledRoute(StringBuffer buffer, _RouteNode node) {
    final base = node.shellFile != null
        ? node.pageFile == null
              ? '${node.shellAlias}.route'
              : '${node.shellAlias}.route.withPage(${node.pageAlias}.route)'
        : node.pageFile != null
        ? '${node.pageAlias}.route'
        : node.routeFile != null
        ? '${node.routeAlias}.route'
        : 'AppRoute<NoParams, NoSearch, NoData>()';
    buffer
      ..writeln('final ${node.variable} = $base.compiled(')
      ..writeln('  path: ${jsonEncode(node.path)},')
      ..writeln('  terminal: ${node.pageFile != null},');
    final contract = node.contract;
    if (contract?.paramsSchema ?? false) {
      _writeParamsCodec(buffer, node, contract!.params!);
    }
    if (contract?.searchSchema ?? false) {
      _writeSearchCodec(buffer, node, contract!.search!);
    }
    if (node.children.isNotEmpty) {
      buffer
        ..writeln('  children: <AnyAppRoute>[')
        ..writeAll(node.children.map((child) => '    ${child.variable},\n'))
        ..writeln('  ],');
    }
    buffer
      ..writeln(');')
      ..writeln();
  }

  void _writeParamsCodec(
    StringBuffer buffer,
    _RouteNode node,
    _RecordContract record,
  ) {
    buffer
      ..writeln('  params: PathParams<${node.routeAlias}.Params>.codec(')
      ..writeln('    decode: (input) => (');
    for (final field in record.fields) {
      buffer.writeln('      ${field.name}: ${_pathDecode(field)},');
    }
    buffer
      ..writeln('    ),')
      ..writeln('    encode: (value, output) {');
    for (final field in record.fields) {
      buffer.writeln('      ${_pathEncode(field)}');
    }
    buffer
      ..writeln('    },')
      ..writeln('  ),');
  }

  void _writeSearchCodec(
    StringBuffer buffer,
    _RouteNode node,
    _RecordContract record,
  ) {
    final defaults = '${node.routeAlias}.route.search!.defaults';
    buffer
      ..writeln('  search: SearchParams<${node.routeAlias}.Search>.codec(')
      ..writeln(
        '    keys: const <String>{${record.fields.map((field) => jsonEncode(field.name)).join(', ')}},',
      )
      ..writeln('    defaults: $defaults,')
      ..writeln('    invalid: ${node.routeAlias}.route.search!.invalid,')
      ..writeln('    decode: (input) => (');
    for (final field in record.fields) {
      buffer.writeln('      ${field.name}: ${_searchDecode(field, defaults)},');
    }
    buffer
      ..writeln('    ),')
      ..writeln('    encode: (value, output) {');
    for (final field in record.fields) {
      buffer.writeln('      ${_searchEncode(field, defaults)}');
    }
    buffer
      ..writeln('    },')
      ..writeln('  ),');
  }

  void _writeFacade(StringBuffer buffer, _RouteNode node) {
    buffer
      ..writeln('final class ${node.className} {')
      ..writeln('  const ${node.className}();');
    for (final child in node.children) {
      buffer
        ..writeln()
        ..writeln(
          '  final ${child.className} ${child.memberName} = '
          'const ${child.className}();',
        );
    }
    if (node.pageFile != null) {
      final params = node.allParams;
      final searchOwners = node.lineage
          .where((owner) => owner.contract?.search != null)
          .toList(growable: false);
      buffer.writeln();
      if (params.isEmpty && searchOwners.isEmpty) {
        buffer.writeln('  Destination to() {');
      } else {
        buffer.writeln('  Destination to({');
      }
      if (params.isNotEmpty) {
        buffer.writeln('    required ${_recordType(params)} params,');
      }
      for (final owner in searchOwners) {
        buffer.writeln(
          '    ${owner.routeAlias}.Search? '
          '${owner.searchArgumentName(target: node)},',
        );
      }
      if (params.isNotEmpty || searchOwners.isNotEmpty) {
        buffer.writeln('  }) {');
      }
      final lineage = node.lineage;
      for (var index = 0; index < lineage.length; index++) {
        final ancestor = lineage[index];
        final local =
            ancestor.contract?.params?.fields ?? const <_RouteField>[];
        final arguments = <String>[];
        if (local.isNotEmpty) {
          arguments.add(
            'params: '
            '(${local.map((field) => '${field.name}: params.${field.name}').join(', ')},)',
          );
        }
        if (ancestor.contract?.search != null) {
          arguments.add('search: ${ancestor.searchArgumentName(target: node)}');
        }
        final ref = '${ancestor.variable}.ref(${arguments.join(', ')})';
        if (index == 0) {
          buffer.write('    return $ref');
        } else {
          buffer.write('.then($ref)');
        }
      }
      buffer
        ..writeln('.destination;')
        ..writeln('  }');
    }
    buffer
      ..writeln('}')
      ..writeln();
  }

  String _recordType(List<_RouteField> fields) =>
      '({${fields.map((field) => '${_qualifiedType(field)} ${field.name}').join(', ')}})';

  String _qualifiedType(_RouteField field) {
    final type = field.type;
    final bare = type.endsWith('?') ? type.substring(0, type.length - 1) : type;
    final suffix = type.endsWith('?') ? '?' : '';
    if (const <String>{'String', 'int', 'double', 'bool'}.contains(bare)) {
      return '$bare$suffix';
    }
    if (bare == 'List<String>') return 'List<String>$suffix';
    if (const <String>{
      'num',
      'BigInt',
      'DateTime',
      'Duration',
      'Uri',
      'Object',
      'dynamic',
      'Never',
    }.contains(bare)) {
      return '$bare$suffix';
    }
    return '${field.owner!.routeAlias}.$bare$suffix';
  }

  bool _schemaFieldsSupported(List<_RouteField> fields, {required bool path}) =>
      fields.every((field) {
        final type = field.type.replaceAll('?', '');
        if (path && field.type.endsWith('?')) return false;
        if (!path && field.type == 'List<String>?') return false;
        return const <String>{
          'String',
          'int',
          'double',
          'bool',
          'List<String>',
        }.contains(type);
      });

  String _pathDecode(_RouteField field) => switch (field.type) {
    'String' => "input.requiredString('${field.name}')",
    'int' => "input.requiredInt('${field.name}')",
    'double' => "input.requiredDouble('${field.name}')",
    'bool' => "input.requiredBool('${field.name}')",
    'List<String>' => "input.segments('${field.name}')",
    _ => throw StateError('Unsupported generated path type ${field.type}.'),
  };

  String _pathEncode(_RouteField field) => switch (field.type) {
    'String' => "output.string('${field.name}', value.${field.name});",
    'int' => "output.integer('${field.name}', value.${field.name});",
    'double' => "output.decimal('${field.name}', value.${field.name});",
    'bool' => "output.boolean('${field.name}', value.${field.name});",
    'List<String>' => "output.segments('${field.name}', value.${field.name});",
    _ => throw StateError('Unsupported generated path type ${field.type}.'),
  };

  String _searchDecode(_RouteField field, String defaults) {
    final type = field.type.replaceAll('?', '');
    final read = switch (type) {
      'String' => "input.string('${field.name}')",
      'int' => "input.integer('${field.name}')",
      'double' => "input.decimal('${field.name}')",
      'bool' => "input.boolean('${field.name}')",
      'List<String>' => "input.strings('${field.name}')",
      _ => throw StateError('Unsupported generated search type ${field.type}.'),
    };
    if (type == 'List<String>') {
      return "input.strings('${field.name}', "
          'fallback: $defaults.${field.name})';
    }
    return '$read ?? $defaults.${field.name}';
  }

  String _searchEncode(_RouteField field, String defaults) {
    final type = field.type.replaceAll('?', '');
    final method = switch (type) {
      'String' => 'string',
      'int' => 'integer',
      'double' => 'decimal',
      'bool' => 'boolean',
      'List<String>' => 'strings',
      _ => throw StateError('Unsupported generated search type ${field.type}.'),
    };
    return "output.$method('${field.name}', value.${field.name}, "
        'omitIf: $defaults.${field.name});';
  }

  void _flatten(_RouteNode node, List<_RouteNode> output) {
    output.add(node);
    for (final child in node.children) {
      _flatten(child, output);
    }
  }

  String _segmentPath(String name) {
    if (name.startsWith('(') && name.endsWith(')')) return '';
    return name;
  }

  bool _validDirectoryName(String name) =>
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name) ||
      RegExp(r'^\[[A-Za-z_][A-Za-z0-9_]*\]$').hasMatch(name) ||
      RegExp(r'^\[\.\.\.[A-Za-z_][A-Za-z0-9_]*\]$').hasMatch(name) ||
      RegExp(r'^\([A-Za-z_][A-Za-z0-9_-]*\)$').hasMatch(name);

  Set<String> _dynamicNames(String path) {
    final match = RegExp(
      r'^\[(?:\.\.\.)?([A-Za-z_][A-Za-z0-9_]*)\]$',
    ).firstMatch(path);
    return match == null ? const <String>{} : <String>{match.group(1)!};
  }

  bool _isRestPath(String path) => path.startsWith('[...');

  bool _isNamedType(String source, String name) =>
      source == name || source.endsWith('.$name');

  String _relative(String path) => p.relative(path, from: projectRoot.path);

  void _error(
    List<FileRouteDiagnostic> diagnostics,
    String path,
    String message,
  ) {
    diagnostics.add(
      FileRouteDiagnostic(
        severity: FileRouteDiagnosticSeverity.error,
        path: _relative(path),
        message: message,
      ),
    );
  }
}

final class _RouteNode {
  _RouteNode({
    required this.directory,
    required this.segments,
    required this.path,
    required this.routeFile,
    required this.pageFile,
    required this.shellFile,
    required this.serverFile,
  });

  final Directory directory;
  final List<String> segments;
  final String path;
  final File? routeFile;
  final File? pageFile;
  final File? shellFile;
  final File? serverFile;
  final List<_RouteNode> children = <_RouteNode>[];
  _RouteContract? contract;
  _RouteNode? parent;

  bool get hasContent =>
      routeFile != null ||
      pageFile != null ||
      shellFile != null ||
      serverFile != null ||
      children.isNotEmpty;

  String get key => segments.isEmpty
      ? 'Root'
      : segments.map(_identifierPart).map(_upperFirst).join();

  String get variable => '_route$key';
  String get className => segments.isEmpty ? 'AppRoutes' : 'App${key}Routes';
  String get memberName => segments.isEmpty ? 'root' : _member(segments.last);
  String get routeAlias => '_${_lowerFirst(key)}Definition';
  String get pageAlias => '_${_lowerFirst(key)}Page';
  String get shellAlias => '_${_lowerFirst(key)}Shell';

  String get effectivePattern {
    final parts = lineage
        .map((node) => node.path)
        .where((part) => part.isNotEmpty && part != '/')
        .map(
          (part) => part.startsWith('[...')
              ? '[...]'
              : part.startsWith('[')
              ? '[]'
              : part,
        )
        .toList(growable: false);
    return parts.isEmpty ? '/' : '/${parts.join('/')}';
  }

  String searchArgumentName({required _RouteNode target}) =>
      identical(this, target) ? 'search' : '${_lowerFirst(key)}Search';

  List<_RouteNode> get lineage {
    final values = <_RouteNode>[];
    _RouteNode? current = this;
    while (current != null) {
      values.add(current);
      current = current.parent;
    }
    return values.reversed.toList(growable: false);
  }

  List<_RouteField> get allParams => lineage
      .expand((node) => node.contract?.params?.fields ?? const <_RouteField>[])
      .toList(growable: false);

  Iterable<_Import> imports(String from) sync* {
    if (routeFile case final file?) {
      yield _Import(_importUri(file, from), routeAlias);
    }
    if (pageFile case final file?) {
      yield _Import(_importUri(file, from), pageAlias);
    }
    if (shellFile case final file?) {
      yield _Import(_importUri(file, from), shellAlias);
    }
  }

  static String _importUri(File file, String from) =>
      p.relative(file.path, from: from).split(p.separator).join('/');

  static String _identifierPart(String value) {
    final result = value
        .replaceAll('[...', 'rest_')
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .split(RegExp(r'[-_]'))
        .where((part) => part.isNotEmpty)
        .map(_upperFirst)
        .join();
    return result.isNotEmpty && RegExp(r'^[0-9]').hasMatch(result)
        ? 'Route$result'
        : result;
  }

  static String _member(String value) {
    final result = _lowerFirst(_identifierPart(value));
    return _reservedMembers.contains(result) ? '${result}Route' : result;
  }

  static const _reservedMembers = <String>{
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'base',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'Function',
    'get',
    'hide',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'late',
    'library',
    'mixin',
    'new',
    'null',
    'of',
    'on',
    'operator',
    'part',
    'required',
    'rethrow',
    'return',
    'sealed',
    'set',
    'show',
    'static',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'true',
    'try',
    'type',
    'typedef',
    'var',
    'void',
    'when',
    'while',
    'with',
    'yield',
    'to',
    'routes',
    'routeTree',
  };

  static String _upperFirst(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  static String _lowerFirst(String value) =>
      value.isEmpty ? value : '${value[0].toLowerCase()}${value.substring(1)}';
}

final class _RouteContract {
  const _RouteContract({
    required this.params,
    required this.search,
    required this.paramsSchema,
    required this.searchSchema,
    required this.declaresParams,
    required this.declaresSearch,
  });

  final _RecordContract? params;
  final _RecordContract? search;
  final bool paramsSchema;
  final bool searchSchema;
  final bool declaresParams;
  final bool declaresSearch;
}

final class _RecordContract {
  const _RecordContract({required this.name, required this.fields});

  final String name;
  final List<_RouteField> fields;
}

final class _RouteField {
  _RouteField({required this.name, required this.type});

  final String name;
  final String type;
  _RouteNode? owner;
}

final class _Import {
  const _Import(this.uri, this.alias);

  final String uri;
  final String alias;
}
