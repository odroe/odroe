import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import 'model.dart';
import 'wire_codec.dart';

/// Discovers server bindings and RPC functions in `server.dart`.
final class ServerFunctionScanner {
  /// Creates a scanner rooted at [projectRoot].
  ServerFunctionScanner(this.projectRoot)
    : _packageName = _projectPackageName(projectRoot);

  /// Application package root used to render diagnostics.
  final Directory projectRoot;
  final String? _packageName;
  final Map<String, _WireLibrary> _wireLibraries = <String, _WireLibrary>{};

  /// Adds declarations from [file] to [node].
  void scan(RouteNode node, File file, List<FileRouteDiagnostic> diagnostics) {
    final result = parseString(
      content: file.readAsStringSync(),
      path: file.path,
      throwIfDiagnostics: false,
    );
    for (final error in result.errors) {
      _error(diagnostics, file.path, error.message);
    }
    if (result.errors.isNotEmpty) return;
    final localTypes = _declaredTypeNames(result.unit);
    final importedTypes = _unprefixedImportedNames(result.unit, file);
    final shadowedTypes = <String>{...localTypes, ...importedTypes};
    final shadowsServerFunction =
        shadowedTypes.contains('ServerFunction') ||
        result.unit.declarations.any((declaration) {
          return switch (declaration) {
            FunctionDeclaration(:final name) => name.lexeme == 'ServerFunction',
            TopLevelVariableDeclaration(:final variables) =>
              variables.variables.any(
                (variable) => variable.name.lexeme == 'ServerFunction',
              ),
            _ => false,
          };
        });

    for (final directive
        in result.unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == null) continue;
      final combinators = _namespaceCombinators(directive);
      node.serverImports.add(
        ServerImport(
          uri: uri,
          prefix: directive.prefix?.name,
          deferred: directive.deferredKeyword != null,
          conditional: directive.configurations.isNotEmpty,
          shownNames: combinators.shown == null
              ? null
              : Set<String>.unmodifiable(combinators.shown!),
          hiddenNames: Set<String>.unmodifiable(combinators.hidden),
        ),
      );
    }
    final wireShapes = _WireShapeResolver(
      projectRoot: projectRoot,
      serverFile: file,
      imports: node.serverImports,
      unprefixedProtocolNames: _visibleProtocolNames(node.serverImports),
      packageName: _packageName,
      libraries: _wireLibraries,
    );

    var exportsRoute = false;
    for (final declaration
        in result.unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      for (final variable in declaration.variables.variables) {
        final name = variable.name.lexeme;
        if (name == 'route') {
          exportsRoute = true;
          final initializer = variable.initializer;
          final arguments = switch (initializer) {
            InstanceCreationExpression() => initializer.argumentList,
            MethodInvocation() => initializer.argumentList,
            _ => null,
          };
          node.serverTerminal =
              arguments?.arguments.whereType<NamedExpression>().any(
                (argument) => argument.name.label.name == 'handlers',
              ) ??
              false;
          continue;
        }
        final initializer = variable.initializer;
        final (
          typeName,
          owner,
          typeArguments,
          argumentList,
        ) = switch (initializer) {
          InstanceCreationExpression() => (
            initializer.constructorName.type.name.lexeme,
            initializer.constructorName.type.importPrefix?.name.lexeme ?? '',
            initializer.constructorName.type.typeArguments,
            initializer.argumentList,
          ),
          MethodInvocation() => (
            initializer.methodName.name,
            switch (initializer.target) {
              null => '',
              SimpleIdentifier(:final name) => name,
              _ => null,
            },
            initializer.typeArguments,
            initializer.argumentList,
          ),
          _ => (null, null, null, null),
        };
        if (typeName != 'ServerFunction' ||
            owner == null ||
            !_ownsServerFunction(
              owner.isEmpty ? null : owner,
              node.serverImports,
              shadowsServerFunction,
            )) {
          continue;
        }
        final arguments = typeArguments?.arguments;
        if (arguments == null || arguments.length != 2) {
          _error(
            diagnostics,
            file.path,
            'ServerFunction "$name" must declare input and output types.',
          );
          continue;
        }
        if (name.startsWith('_')) {
          _error(
            diagnostics,
            file.path,
            'ServerFunction "$name" must be public so generated code can bind it.',
          );
          continue;
        }
        final input = arguments[0].toSource();
        final output = arguments[1];
        final unsharedTypes = <String>{};
        for (final type in arguments) {
          type.accept(_ClientTypeVisitor(unsharedTypes, shadowedTypes));
        }
        if (unsharedTypes.isNotEmpty) {
          _error(
            diagnostics,
            file.path,
            'ServerFunction "$name" uses client-visible type(s) '
            '${unsharedTypes.join(', ')} without an import prefix. Put domain '
            'types in a shared library and import it with a prefix.',
          );
          continue;
        }
        final stream =
            output is NamedType && _isStreamType(output, node.serverImports)
            ? output
            : null;
        if (stream?.question != null) {
          _error(
            diagnostics,
            file.path,
            'ServerFunction "$name" has an unsupported wire type: '
            '${output.toSource()} is nullable; stream outputs must be non-null',
          );
          continue;
        }
        final streamType = stream?.typeArguments?.arguments.length == 1
            ? stream!.typeArguments!.arguments.single
            : null;
        late final WireShape inputWireShape;
        late final WireShape outputWireShape;
        try {
          inputWireShape = wireShapes.resolve(
            arguments[0],
            input: true,
            label: input,
          );
          outputWireShape = wireShapes.resolve(
            streamType ?? output,
            input: false,
            label: streamType?.toSource() ?? output.toSource(),
            direct: streamType == null,
          );
        } on _WireShapeException catch (error) {
          _error(
            diagnostics,
            file.path,
            'ServerFunction "$name" has an unsupported wire type: '
            '${error.message}',
          );
          continue;
        }
        String? explicitId;
        var method = 'HttpMethod.post';
        for (final argument
            in argumentList!.arguments.whereType<NamedExpression>()) {
          switch (argument.name.label.name) {
            case 'id':
              final expression = argument.expression;
              final value = expression is StringLiteral
                  ? expression.stringValue
                  : null;
              if (value == null) {
                _error(
                  diagnostics,
                  file.path,
                  'ServerFunction "$name" id must be a string literal.',
                );
              } else if (value.isEmpty) {
                _error(
                  diagnostics,
                  file.path,
                  'ServerFunction "$name" id must not be empty.',
                );
              } else {
                explicitId = value;
              }
            case 'method':
              final source = argument.expression.toSource();
              if (!RegExp(
                r'^(?:[A-Za-z_]\w*\.)?HttpMethod\.[a-z]+$',
              ).hasMatch(source)) {
                _error(
                  diagnostics,
                  file.path,
                  'ServerFunction "$name" method must be a HttpMethod value.',
                );
              } else {
                method = 'HttpMethod.${source.split('.').last}';
              }
          }
        }
        final relativePath = _relative(file.path).split(p.separator).join('/');
        node.functions.add(
          ServerFunctionDeclaration(
            name: name,
            wireId: explicitId ?? '$relativePath#$name',
            inputType: input,
            outputType: output.toSource(),
            streamType: streamType?.toSource(),
            method: method,
            inputWireShape: inputWireShape,
            outputWireShape: outputWireShape,
          ),
        );
      }
    }
    if (!exportsRoute) {
      _error(
        diagnostics,
        file.path,
        'File must export a top-level variable named route.',
      );
    }
  }

  String _relative(String path) => p.relative(path, from: projectRoot.path);

  bool _isStreamType(NamedType type, List<ServerImport> imports) {
    if (type.name.lexeme != 'Stream') return false;
    final prefix = type.importPrefix?.name.lexeme;
    if (prefix == null) return true;
    final matching = imports
        .where((import) => import.prefix == prefix)
        .toList(growable: false);
    return matching.length == 1 &&
        matching.single.uri == 'dart:async' &&
        !matching.single.conditional &&
        !matching.single.deferred &&
        matching.single.exposes('Stream');
  }

  bool _ownsServerFunction(
    String? prefix,
    List<ServerImport> imports,
    bool shadowed,
  ) {
    if (prefix == null && shadowed) return false;
    final matching = imports
        .where((import) => import.prefix == prefix)
        .toList(growable: false);
    if (prefix == null) {
      return matching.any(
        (import) =>
            _odroeServerEntrypoints.contains(import.uri) &&
            !import.conditional &&
            !import.deferred &&
            import.exposes('ServerFunction'),
      );
    }
    final visible = matching
        .where((import) => import.exposes('ServerFunction'))
        .toList(growable: false);
    return visible.isNotEmpty &&
        visible.every(
          (import) =>
              _odroeServerEntrypoints.contains(import.uri) &&
              !import.conditional &&
              !import.deferred,
        );
  }

  Set<String> _visibleProtocolNames(List<ServerImport> imports) {
    const names = <String>{'NoServerInput', 'ServerResponse'};
    return <String>{
      for (final import in imports)
        if (import.prefix == null &&
            !import.conditional &&
            !import.deferred &&
            _WireShapeResolver._isOdroeProtocolImport(import.uri))
          ...names.where(import.exposes),
    };
  }

  Set<String> _unprefixedImportedNames(CompilationUnit unit, File sourceFile) {
    final names = <String>{};
    for (final import in unit.directives.whereType<ImportDirective>()) {
      if (import.prefix != null) continue;
      final uri = import.uri.stringValue;
      if (uri == null ||
          _unprefixedBuiltInImports.contains(uri) ||
          _WireShapeResolver._isOdroeProtocolImport(uri)) {
        continue;
      }
      final visible = _visibleNames(import, sourceFile);
      names.addAll(visible);
    }
    return names;
  }

  Set<String> _visibleNames(
    NamespaceDirective directive,
    File sourceFile, {
    Set<String>? visited,
  }) {
    final combinators = _namespaceCombinators(directive);
    final shown = combinators.shown;
    final uris = <String?>[
      directive.uri.stringValue,
      ...directive.configurations.map(
        (configuration) => configuration.uri.stringValue,
      ),
    ];
    final names = <String>{};
    for (final uri in uris) {
      final importedFile = uri == null
          ? null
          : _projectFileFor(
              projectRoot,
              sourceFile,
              uri,
              packageName: _packageName,
            );
      if (importedFile != null && importedFile.existsSync()) {
        names.addAll(_projectLibraryNames(importedFile, visited ?? <String>{}));
      } else if (shown != null) {
        names.addAll(shown);
      }
    }
    if (shown != null) names.retainAll(shown);
    names.removeAll(combinators.hidden);
    return names;
  }

  Set<String> _projectLibraryNames(File file, Set<String> visited) {
    final path = p.normalize(file.absolute.path);
    if (!visited.add(path)) return <String>{};
    try {
      final result = parseString(
        content: file.readAsStringSync(),
        path: file.path,
        throwIfDiagnostics: false,
      );
      if (result.errors.isNotEmpty) return <String>{};
      final names = _declaredTopLevelNames(result.unit);
      for (final directive in result.unit.directives) {
        if (directive is ExportDirective) {
          names.addAll(_visibleNames(directive, file, visited: visited));
        } else if (directive is PartDirective) {
          final uri = directive.uri.stringValue;
          final part = uri == null
              ? null
              : _projectFileFor(
                  projectRoot,
                  file,
                  uri,
                  packageName: _packageName,
                );
          if (part == null || !part.existsSync()) continue;
          final partResult = parseString(
            content: part.readAsStringSync(),
            path: part.path,
            throwIfDiagnostics: false,
          );
          if (partResult.errors.isEmpty) {
            names.addAll(_declaredTopLevelNames(partResult.unit));
          }
        }
      }
      names.removeWhere((name) => name.startsWith('_'));
      return names;
    } finally {
      visited.remove(path);
    }
  }

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

WireShape _renameWireShape(
  WireShape shape, {
  required String source,
  required bool nullable,
}) => switch (shape) {
  WireValueShape() => WireValueShape(source: source, nullable: nullable),
  WireCollectionShape(:final kind, :final value) => WireCollectionShape(
    source: source,
    nullable: nullable,
    kind: kind,
    value: value,
  ),
  WireRecordShape(:final fields) => WireRecordShape(
    source: source,
    nullable: nullable,
    fields: fields,
  ),
};

final class _WireShapeResolver {
  _WireShapeResolver({
    required this.projectRoot,
    required this.serverFile,
    required List<ServerImport> imports,
    required Set<String> unprefixedProtocolNames,
    required String? packageName,
    required Map<String, _WireLibrary> libraries,
  }) : _imports = _indexImports(imports),
       _unprefixedProtocolNames = unprefixedProtocolNames,
       _packageName = packageName,
       _libraries = libraries;

  final Directory projectRoot;
  final File serverFile;
  final String? _packageName;
  final Map<String, List<ServerImport>> _imports;
  final Set<String> _unprefixedProtocolNames;
  final Map<String, _WireLibrary> _libraries;

  WireShape resolve(
    TypeAnnotation annotation, {
    required bool input,
    required String label,
    bool direct = true,
  }) => _resolve(
    annotation,
    input: input,
    topLevel: direct,
    label: label,
    library: null,
    stack: const <String>[],
  );

  WireShape _resolve(
    TypeAnnotation annotation, {
    required bool input,
    required bool topLevel,
    required String label,
    required _WireLibrary? library,
    required List<String> stack,
  }) {
    if (annotation is GenericFunctionType) {
      throw _WireShapeException('$label is not JSON serializable');
    }
    if (annotation is RecordTypeAnnotation) {
      if (annotation.positionalFields.isNotEmpty) {
        throw _WireShapeException(
          '$label uses a positional record; only named-record typedefs are supported',
        );
      }
      throw _WireShapeException(
        '$label is an inline record; declare it as a project-local named-record '
        'typedef and import that library with a prefix',
      );
    }
    final type = annotation as NamedType;
    final prefix = type.importPrefix?.name.lexeme;
    if (prefix != null) {
      if (library != null) {
        throw _WireShapeException(
          '$label uses prefixed type ${type.toSource()} inside '
          'a project-local record typedef; imported record fields must use '
          'built-in or same-library types',
        );
      }
      return _resolvePrefixed(
        type,
        prefix,
        input: input,
        topLevel: topLevel,
        label: label,
        stack: stack,
      );
    }
    return _resolveUnprefixed(
      type,
      input: input,
      topLevel: topLevel,
      label: label,
      library: library,
      stack: stack,
    );
  }

  WireShape _resolvePrefixed(
    NamedType type,
    String prefix, {
    required bool input,
    required bool topLevel,
    required String label,
    required List<String> stack,
  }) {
    final imports = _imports[prefix];
    if (imports == null) {
      throw _WireShapeException('$label uses unknown import prefix "$prefix"');
    }
    if (imports.length != 1) {
      throw _WireShapeException(
        '$label uses import prefix "$prefix" for multiple libraries; shared '
        'import prefixes are not supported for wire types',
      );
    }
    final import = imports.single;
    if (!import.exposes(type.name.lexeme)) {
      throw _WireShapeException(
        '$label uses ${type.toSource()}, but import prefix "$prefix" does not '
        'expose ${type.name.lexeme}',
      );
    }
    if (import.conditional) {
      throw _WireShapeException(
        '$label uses conditional import prefix "$prefix"; conditional imports '
        'are not supported for wire types',
      );
    }
    if (import.deferred) {
      throw _WireShapeException(
        '$label uses deferred import prefix "$prefix"; wire types must be '
        'available synchronously',
      );
    }
    if (type.name.lexeme.startsWith('_')) {
      throw _WireShapeException(
        '$label uses private type ${type.toSource()}; wire types must be public',
      );
    }
    if (_clientUnsafeSdkImports.contains(import.uri)) {
      throw _WireShapeException(
        '$label uses ${type.toSource()} from ${import.uri}; wire types must be '
        'available to both client and server targets',
      );
    }
    if (import.uri == 'dart:core') {
      throw _WireShapeException(
        '$label uses dart:core type ${type.toSource()} with an import prefix; '
        'core wire types must be unprefixed',
      );
    }
    if (import.uri == 'dart:async' &&
        (type.name.lexeme == 'Future' ||
            type.name.lexeme == 'FutureOr' ||
            type.name.lexeme == 'Stream')) {
      throw _WireShapeException(
        '${type.toSource()} at $label is not a value wire type',
      );
    }
    if (_isOdroeProtocolImport(import.uri)) {
      final name = type.name.lexeme;
      final arguments =
          type.typeArguments?.arguments ?? const <TypeAnnotation>[];
      final nullable = type.question != null;
      if (name == 'NoServerInput') {
        if (input && topLevel && !nullable && arguments.isEmpty) {
          return WireValueShape(source: type.toSource(), nullable: false);
        }
        throw const _WireShapeException(
          'NoServerInput is only valid as direct input',
        );
      }
      if (name == 'ServerResponse') {
        if (!input && topLevel && !nullable && arguments.isEmpty) {
          return WireValueShape(source: type.toSource(), nullable: false);
        }
        throw const _WireShapeException(
          'ServerResponse is only valid as direct output',
        );
      }
      if (_isOdroeServerOnlyImport(import.uri)) {
        throw _WireShapeException(
          '$label uses server-only type ${type.toSource()}; move wire types to '
          'a client-safe shared library',
        );
      }
    }
    if (_targetSpecificOdroeImports.contains(import.uri)) {
      throw _WireShapeException(
        '$label uses ${type.toSource()} from target-specific entrypoint '
        '${import.uri}; move wire types to a client-safe shared library',
      );
    }
    if (import.uri == 'dart:typed_data') {
      final name = type.name.lexeme;
      if (name != 'Uint8List') {
        throw _WireShapeException('$name at $label has no built-in serializer');
      }
      if (type.typeArguments != null) {
        throw _WireShapeException(
          'Uint8List at $label does not accept type arguments',
        );
      }
      return WireValueShape(
        source: type.toSource(),
        nullable: type.question != null,
      );
    }
    final importedFile = _projectFile(import.uri);
    if (importedFile == null) {
      final uri = Uri.tryParse(import.uri);
      final localUri =
          uri == null ||
          !uri.hasScheme ||
          (uri.scheme == 'package' &&
              (uri.pathSegments.isEmpty ||
                  uri.pathSegments.first == _packageName));
      if (localUri) {
        throw _WireShapeException(
          '$label uses wire import ${import.uri}, which is outside the project',
        );
      }
      _validateNominalTypeArguments(
        type,
        input: input,
        label: label,
        stack: stack,
      );
      return WireValueShape(
        source: type.toSource(),
        nullable: type.question != null,
      );
    }
    if (!importedFile.existsSync()) {
      throw _WireShapeException(
        '$label uses missing wire import ${import.uri}',
      );
    }
    final library = _loadLibrary(importedFile, prefix);
    final alias = library.aliases[type.name.lexeme];
    if (alias == null) {
      if (!library.nominalTypes.contains(type.name.lexeme)) {
        throw _WireShapeException(
          '$label uses ${type.toSource()}, which is not declared directly in '
          '${p.relative(importedFile.path, from: projectRoot.path)}; parts and '
          're-exports are not inspected for wire types',
        );
      }
      _validateNominalTypeArguments(
        type,
        input: input,
        label: label,
        stack: stack,
      );
      return WireValueShape(
        source: type.toSource(),
        nullable: type.question != null,
      );
    }
    return _resolveAlias(
      library,
      alias,
      reference: type,
      input: input,
      topLevel: topLevel,
      label: label,
      stack: stack,
    );
  }

  void _validateNominalTypeArguments(
    NamedType type, {
    required bool input,
    required String label,
    required List<String> stack,
  }) {
    final arguments = type.typeArguments?.arguments;
    if (arguments == null) return;
    for (var index = 0; index < arguments.length; index++) {
      _resolve(
        arguments[index],
        input: input,
        topLevel: false,
        label: '$label type argument ${index + 1}',
        library: null,
        stack: stack,
      );
    }
  }

  WireShape _resolveUnprefixed(
    NamedType type, {
    required bool input,
    required bool topLevel,
    required String label,
    required _WireLibrary? library,
    required List<String> stack,
  }) {
    final name = type.name.lexeme;
    final arguments = type.typeArguments?.arguments ?? const <TypeAnnotation>[];
    final nullable = type.question != null;
    if (library != null) {
      if (name.startsWith('_')) {
        throw _WireShapeException(
          '$label uses private type $name from ${library.file.path}',
        );
      }
      final alias = library.aliases[name];
      if (alias != null) {
        return _resolveAlias(
          library,
          alias,
          reference: type,
          input: input,
          topLevel: topLevel,
          label: label,
          stack: stack,
        );
      }
      if (library.nominalTypes.contains(name)) {
        if (arguments.isNotEmpty) {
          throw _WireShapeException(
            '$label uses unsupported generic same-library type $name',
          );
        }
        return WireValueShape(
          source: '${library.prefix}.$name${nullable ? '?' : ''}',
          nullable: nullable,
        );
      }
      if (library.importedTypes.contains(name)) {
        throw _WireShapeException(
          '$label uses imported type $name; record field types must be '
          'declared in the same source file as their record typedef',
        );
      }
    }
    if (_wireBuiltInTypes.contains(name)) {
      if (name == 'Future' ||
          name == 'FutureOr' ||
          name == 'Stream' ||
          name == 'Never') {
        throw _WireShapeException(
          '${type.toSource()} at $label is not a value wire type',
        );
      }
      if (name == 'void') {
        if (!input && topLevel && !nullable && arguments.isEmpty) {
          return const WireValueShape(source: 'void', nullable: false);
        }
        throw const _WireShapeException('void is only valid as direct output');
      }
      if (name == 'NoServerInput') {
        if (library == null &&
            !_unprefixedProtocolNames.contains('NoServerInput')) {
          throw const _WireShapeException(
            'NoServerInput does not resolve to a visible Odroe protocol type; '
            'import package:odroe/server.dart or package:odroe/rpc.dart '
            'without hiding it',
          );
        }
        if (input && topLevel && !nullable && arguments.isEmpty) {
          return const WireValueShape(source: 'NoServerInput', nullable: false);
        }
        throw const _WireShapeException(
          'NoServerInput is only valid as direct input',
        );
      }
      if (name == 'ServerResponse') {
        if (library == null &&
            !_unprefixedProtocolNames.contains('ServerResponse')) {
          throw const _WireShapeException(
            'ServerResponse does not resolve to a visible Odroe protocol '
            'type; import package:odroe/server.dart or '
            'package:odroe/rpc.dart without hiding it',
          );
        }
        if (!input && topLevel && !nullable && arguments.isEmpty) {
          return const WireValueShape(
            source: 'ServerResponse',
            nullable: false,
          );
        }
        throw const _WireShapeException(
          'ServerResponse is only valid as direct output',
        );
      }
      if (_unsupportedTypedData.contains(name)) {
        throw _WireShapeException('$name at $label has no built-in serializer');
      }
      if (name == 'Map') {
        if (arguments.length != 2 || !_isString(arguments.first, library)) {
          throw _WireShapeException(
            '$label must use Map<dart:core String, T> without a shadowed key '
            'type',
          );
        }
        final value = _resolve(
          arguments[1],
          input: input,
          topLevel: false,
          label: '$label value',
          library: library,
          stack: stack,
        );
        return WireCollectionShape(
          source: 'Map<String, ${value.source}>${nullable ? '?' : ''}',
          nullable: nullable,
          kind: WireCollectionKind.map,
          value: value,
        );
      }
      final collection = switch (name) {
        'List' => WireCollectionKind.list,
        'Set' => WireCollectionKind.set,
        'Iterable' => WireCollectionKind.iterable,
        _ => null,
      };
      if (collection != null) {
        if (arguments.length != 1) {
          throw _WireShapeException(
            '$name at $label requires one type argument',
          );
        }
        final value = _resolve(
          arguments.single,
          input: input,
          topLevel: false,
          label: '$label item',
          library: library,
          stack: stack,
        );
        return WireCollectionShape(
          source: '$name<${value.source}>${nullable ? '?' : ''}',
          nullable: nullable,
          kind: collection,
          value: value,
        );
      }
      if (arguments.isNotEmpty) {
        throw _WireShapeException(
          '$name at $label does not accept type arguments',
        );
      }
      return WireValueShape(
        source: '$name${nullable ? '?' : ''}',
        nullable: nullable,
      );
    }
    if (library == null) {
      throw _WireShapeException(
        '$label uses client-visible type $name without an import prefix',
      );
    }
    throw _WireShapeException(
      '$label uses $name, which is not declared in the same source file as '
      'its record typedef; imported and re-exported record field types are '
      'not inspected',
    );
  }

  WireShape _resolveAlias(
    _WireLibrary library,
    GenericTypeAlias alias, {
    required NamedType reference,
    required bool input,
    required bool topLevel,
    required String label,
    required List<String> stack,
  }) {
    final key = '${library.file.path}#${alias.name.lexeme}';
    if (stack.contains(key)) {
      final cycle = <String>[...stack, key]
          .map((entry) => entry.substring(entry.lastIndexOf('#') + 1))
          .join(' -> ');
      throw _WireShapeException('$label contains a type-alias cycle: $cycle');
    }
    final nextStack = <String>[...stack, key];
    final typeParameters = alias.typeParameters?.typeParameters;
    if (typeParameters != null && typeParameters.isNotEmpty) {
      throw _WireShapeException(
        '$label resolves to generic record typedef '
        '${library.prefix}.${alias.name.lexeme}; generic record typedefs are '
        'not supported',
      );
    }
    if (reference.typeArguments != null) {
      throw _WireShapeException(
        '$label supplies type arguments to non-generic record typedef '
        '${library.prefix}.${alias.name.lexeme}',
      );
    }
    final record = alias.type;
    if (record is! RecordTypeAnnotation) {
      final target = _resolve(
        record,
        input: input,
        topLevel: topLevel,
        label: '$label alias target',
        library: library,
        stack: nextStack,
      );
      if (target.nullable && wireShapeContainsRecord(target)) {
        throw _WireShapeException(
          '$label resolves through a nullable record alias target; put ? on '
          'the function use site instead (${library.prefix}.${alias.name.lexeme}?)',
        );
      }
      final nullable = reference.question != null || target.nullable;
      return _renameWireShape(
        target,
        source: '${library.prefix}.${alias.name.lexeme}${nullable ? '?' : ''}',
        nullable: nullable,
      );
    }
    if (record.question != null) {
      throw _WireShapeException(
        '$label resolves to nullable record typedef '
        '${library.prefix}.${alias.name.lexeme}; make the use site nullable '
        'instead (${library.prefix}.${alias.name.lexeme}?)',
      );
    }
    if (record.positionalFields.isNotEmpty) {
      throw _WireShapeException(
        '$label resolves to positional record typedef '
        '${library.prefix}.${alias.name.lexeme}; only named fields are supported',
      );
    }
    final fields = record.namedFields?.fields;
    if (fields == null || fields.isEmpty) {
      throw _WireShapeException(
        '$label resolves to an empty record; at least one named field is required',
      );
    }
    final resolvedFields = <WireRecordField>[];
    for (final field in fields) {
      if (field.name.lexeme.startsWith('_')) {
        throw _WireShapeException(
          '$label uses private record field ${field.name.lexeme}; record '
          'fields must be public to cross a library boundary',
        );
      }
      resolvedFields.add(
        WireRecordField(
          name: field.name.lexeme,
          shape: _resolve(
            field.type,
            input: input,
            topLevel: false,
            label: '$label.${field.name.lexeme}',
            library: library,
            stack: nextStack,
          ),
        ),
      );
    }
    final nullable = reference.question != null;
    return WireRecordShape(
      source: '${library.prefix}.${alias.name.lexeme}${nullable ? '?' : ''}',
      nullable: nullable,
      fields: List<WireRecordField>.unmodifiable(resolvedFields),
    );
  }

  bool _isString(TypeAnnotation annotation, _WireLibrary? library) =>
      annotation is NamedType &&
      annotation.importPrefix == null &&
      annotation.name.lexeme == 'String' &&
      annotation.typeArguments == null &&
      annotation.question == null &&
      (library == null ||
          (!library.aliases.containsKey('String') &&
              !library.nominalTypes.contains('String') &&
              !library.importedTypes.contains('String')));

  _WireLibrary _loadLibrary(File file, String prefix) {
    final key = '${file.absolute.path}|$prefix';
    return _libraries.putIfAbsent(key, () {
      final result = parseString(
        content: file.readAsStringSync(),
        path: file.path,
        throwIfDiagnostics: false,
      );
      if (result.errors.isNotEmpty) {
        throw _WireShapeException(
          'Cannot inspect ${p.relative(file.path, from: projectRoot.path)}: '
          '${result.errors.first.message}',
        );
      }
      if (result.unit.directives.any(
        (directive) => directive is PartOfDirective,
      )) {
        throw _WireShapeException(
          '${p.relative(file.path, from: projectRoot.path)} is a part file and '
          'cannot be imported directly as a wire library',
        );
      }
      for (final directive
          in result.unit.directives.whereType<NamespaceDirective>()) {
        for (final uri in <String?>[
          directive.uri.stringValue,
          ...directive.configurations.map(
            (configuration) => configuration.uri.stringValue,
          ),
        ]) {
          if (uri != null &&
              (_clientUnsafeSdkImports.contains(uri) ||
                  _targetSpecificOdroeImports.contains(uri))) {
            throw _WireShapeException(
              '${p.relative(file.path, from: projectRoot.path)} references '
              '$uri; shared wire libraries must compile for both client and '
              'server targets',
            );
          }
        }
      }
      return _WireLibrary(
        file: file,
        prefix: prefix,
        aliases: <String, GenericTypeAlias>{
          for (final declaration
              in result.unit.declarations.whereType<GenericTypeAlias>())
            declaration.name.lexeme: declaration,
        },
        nominalTypes: result.unit.declarations
            .map(_nominalTypeName)
            .nonNulls
            .toSet(),
        importedTypes: _importedTypeNames(result.unit, file),
      );
    });
  }

  Set<String> _importedTypeNames(CompilationUnit unit, File libraryFile) {
    final names = <String>{};
    for (final import in unit.directives.whereType<ImportDirective>()) {
      if (import.prefix != null) continue;
      final combinators = _namespaceCombinators(import);
      final importedNames = <String>{};
      final uri = import.uri.stringValue;
      if (const <String>{
        'dart:async',
        'dart:core',
        'dart:typed_data',
      }.contains(uri)) {
        continue;
      }
      final importedFile = uri == null
          ? null
          : _projectFileFrom(libraryFile, uri);
      if (importedFile != null && importedFile.existsSync()) {
        final result = parseString(
          content: importedFile.readAsStringSync(),
          path: importedFile.path,
          throwIfDiagnostics: false,
        );
        if (result.errors.isEmpty) {
          importedNames.addAll(_declaredTypeNames(result.unit));
        }
      } else if (combinators.shown != null) {
        importedNames.addAll(combinators.shown!);
      }
      if (combinators.shown != null) {
        importedNames.retainAll(combinators.shown!);
      }
      importedNames.removeAll(combinators.hidden);
      names.addAll(importedNames);
    }
    return names;
  }

  static Map<String, List<ServerImport>> _indexImports(
    List<ServerImport> imports,
  ) {
    final indexed = <String, List<ServerImport>>{};
    for (final import in imports) {
      final prefix = import.prefix;
      if (prefix != null) (indexed[prefix] ??= <ServerImport>[]).add(import);
    }
    return indexed;
  }

  static bool _isOdroeProtocolImport(String uri) => const <String>{
    'package:odroe/rpc.dart',
    ..._odroeServerEntrypoints,
  }.contains(uri);

  static bool _isOdroeServerOnlyImport(String uri) =>
      _odroeServerEntrypoints.contains(uri);

  File? _projectFile(String source) => _projectFileFrom(serverFile, source);

  File? _projectFileFrom(File sourceFile, String source) => _projectFileFor(
    projectRoot,
    sourceFile,
    source,
    packageName: _packageName,
  );
}

final class _WireLibrary {
  _WireLibrary({
    required this.file,
    required this.prefix,
    required this.aliases,
    required this.nominalTypes,
    required this.importedTypes,
  });

  final File file;
  final String prefix;
  final Map<String, GenericTypeAlias> aliases;
  final Set<String> nominalTypes;
  final Set<String> importedTypes;
}

final class _WireShapeException implements Exception {
  const _WireShapeException(this.message);

  final String message;
}

const Set<String> _wireBuiltInTypes = <String>{
  ..._clientBuiltInTypes,
  'ByteBuffer',
  'ByteData',
  'Float32List',
  'Float64List',
  'Int8List',
  'Int16List',
  'Int32List',
  'Int64List',
  'Uint16List',
  'Uint32List',
  'Uint64List',
};

const Set<String> _unsupportedTypedData = <String>{
  'ByteBuffer',
  'ByteData',
  'Float32List',
  'Float64List',
  'Int8List',
  'Int16List',
  'Int32List',
  'Int64List',
  'Uint16List',
  'Uint32List',
  'Uint64List',
};

const Set<String> _clientUnsafeSdkImports = <String>{
  'dart:cli',
  'dart:concurrent',
  'dart:ffi',
  'dart:html',
  'dart:indexed_db',
  'dart:io',
  'dart:isolate',
  'dart:js',
  'dart:js_interop',
  'dart:js_interop_unsafe',
  'dart:js_util',
  'dart:mirrors',
  'dart:svg',
  'dart:ui',
  'dart:web_audio',
  'dart:web_gl',
};

const Set<String> _targetSpecificOdroeImports = <String>{
  'package:odroe/database_d1.dart',
  'package:odroe/database_mysql.dart',
  'package:odroe/database_postgres.dart',
  'package:odroe/database_sqlite.dart',
  'package:odroe/document_flutter.dart',
  'package:odroe/mdc_flutter.dart',
  'package:odroe/odroe_flutter.dart',
  'package:odroe/press_io.dart',
  'package:odroe/query_flutter.dart',
  'package:odroe/router_flutter.dart',
  ..._odroeServerEntrypoints,
};

const Set<String> _odroeServerEntrypoints = <String>{
  'package:odroe/server.dart',
  'package:odroe/server_fetch.dart',
  'package:odroe/server_io.dart',
};

const Set<String> _clientBuiltInTypes = <String>{
  'BigInt',
  'DateTime',
  'Duration',
  'Future',
  'FutureOr',
  'Iterable',
  'List',
  'Map',
  'Never',
  'NoServerInput',
  'Null',
  'Object',
  'Set',
  'ServerResponse',
  'Stream',
  'String',
  'Uint8List',
  'Uri',
  'bool',
  'double',
  'dynamic',
  'int',
  'num',
  'void',
};

final class _ClientTypeVisitor extends RecursiveAstVisitor<void> {
  _ClientTypeVisitor(this.unsharedTypes, this.localTypes);

  final Set<String> unsharedTypes;
  final Set<String> localTypes;

  @override
  void visitNamedType(NamedType node) {
    final name = node.name.lexeme;
    if (node.importPrefix == null &&
        (localTypes.contains(name) || !_clientBuiltInTypes.contains(name))) {
      unsharedTypes.add(name);
    }
    super.visitNamedType(node);
  }
}

({Set<String>? shown, Set<String> hidden}) _namespaceCombinators(
  NamespaceDirective directive,
) {
  Set<String>? shown;
  final hidden = <String>{};
  for (final combinator in directive.combinators) {
    switch (combinator) {
      case ShowCombinator(:final shownNames):
        final next = shownNames.map((name) => name.name).toSet();
        if (shown == null) {
          shown = next;
        } else {
          shown.retainAll(next);
        }
        shown.removeAll(hidden);
      case HideCombinator(:final hiddenNames):
        final next = hiddenNames.map((name) => name.name);
        hidden.addAll(next);
        shown?.removeAll(next);
    }
  }
  return (shown: shown, hidden: hidden);
}

Set<String> _declaredTypeNames(CompilationUnit unit) {
  final names = <String>{};
  for (final declaration in unit.declarations) {
    if (declaration case TypeAlias(:final name)) names.add(name.lexeme);
    final nominal = _nominalTypeName(declaration);
    if (nominal != null) names.add(nominal);
  }
  return names;
}

Set<String> _declaredTopLevelNames(CompilationUnit unit) {
  final names = _declaredTypeNames(unit);
  for (final declaration in unit.declarations) {
    switch (declaration) {
      case FunctionDeclaration(:final name):
        names.add(name.lexeme);
      case TopLevelVariableDeclaration(:final variables):
        names.addAll(
          variables.variables.map((variable) => variable.name.lexeme),
        );
    }
  }
  return names;
}

File? _projectFileFor(
  Directory rootDirectory,
  File sourceFile,
  String source, {
  required String? packageName,
}) {
  final uri = Uri.tryParse(source);
  String? path;
  if (uri == null || !uri.hasScheme) {
    path = p.normalize(p.join(sourceFile.parent.path, source));
  } else if (uri.scheme == 'package') {
    final segments = uri.pathSegments;
    if (segments.length < 2 || segments.first != packageName) return null;
    path = p.joinAll(<String>[rootDirectory.path, 'lib', ...segments.skip(1)]);
  } else {
    return null;
  }
  final root = p.normalize(rootDirectory.absolute.path);
  final absolute = p.normalize(File(path).absolute.path);
  if (!p.equals(root, absolute) && !p.isWithin(root, absolute)) return null;
  return File(absolute);
}

String? _projectPackageName(Directory rootDirectory) {
  final pubspec = File(p.join(rootDirectory.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  return RegExp(
    r'^name:\s*([A-Za-z0-9_]+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync())?.group(1);
}

String? _nominalTypeName(CompilationUnitMember declaration) =>
    switch (declaration) {
      ClassDeclaration(:final namePart) => namePart.typeName.lexeme,
      ClassTypeAlias(:final name) => name.lexeme,
      EnumDeclaration(:final namePart) => namePart.typeName.lexeme,
      ExtensionTypeDeclaration(:final primaryConstructor) =>
        primaryConstructor.typeName.lexeme,
      MixinDeclaration(:final name) => name.lexeme,
      _ => null,
    };

const Set<String> _unprefixedBuiltInImports = <String>{
  'dart:async',
  'dart:core',
  'dart:typed_data',
};
