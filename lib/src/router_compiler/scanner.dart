import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import 'model.dart';
import 'server_functions.dart';

/// Scans and validates a filesystem route tree.
final class RouteScanner {
  /// Creates a scanner rooted at [projectRoot].
  RouteScanner(this.projectRoot)
    : _serverFunctions = ServerFunctionScanner(projectRoot);

  /// Application package root used for diagnostics and import resolution.
  final Directory projectRoot;
  final ServerFunctionScanner _serverFunctions;

  /// Scans [routesDirectory] into a structural route tree.
  RouteNode scan(
    Directory routesDirectory,
    List<FileRouteDiagnostic> diagnostics,
  ) => _scan(routesDirectory, const <String>[], diagnostics, isRoot: true);

  /// Validates contracts and generated identifiers for [root].
  void validate(
    RouteNode root,
    List<RouteNode> nodes,
    List<FileRouteDiagnostic> diagnostics,
  ) {
    _validateTree(root, diagnostics, <RouteField>[]);
    _validateGeneratedNames(nodes, diagnostics);
  }

  /// Flattens [root] in stable depth-first order.
  List<RouteNode> flatten(RouteNode root) {
    final nodes = <RouteNode>[];
    _flatten(root, nodes);
    return nodes;
  }

  /// Returns terminal locations that need no path parameters.
  List<String> staticRoutes(List<RouteNode> nodes) => _staticRoutes(nodes);

  RouteNode _scan(
    Directory directory,
    List<String> segments,
    List<FileRouteDiagnostic> diagnostics, {
    required bool isRoot,
  }) {
    final routeFile = File(p.join(directory.path, 'route.dart'));
    final pageFile = File(p.join(directory.path, 'page.dart'));
    final shellFile = File(p.join(directory.path, 'shell.dart'));
    final serverFile = File(p.join(directory.path, 'server.dart'));
    final node = RouteNode(
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
      _requireBoundRoute(file, 'page', diagnostics);
      if (node.routeFile == null) {
        _error(
          diagnostics,
          file.path,
          'page.dart requires route.dart as its neutral typed declaration.',
        );
      }
    }
    if (node.shellFile case final file?) {
      _requireBoundRoute(file, 'shell', diagnostics);
      if (node.routeFile == null) {
        _error(
          diagnostics,
          file.path,
          'shell.dart requires route.dart as its neutral typed declaration.',
        );
      }
    }
    if (node.serverFile case final file?) {
      _requireBoundRoute(file, 'server', diagnostics);
      _serverFunctions.scan(node, file, diagnostics);
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

  RouteContract _parseContract(
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

    RecordContract? params;
    RecordContract? search;
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
      final record = RecordContract(
        name: name,
        fields: type.namedFields!.fields
            .map(
              (field) => RouteField(
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
    final appRoute = _appRouteCreation(initializer);
    final isAppRoute = appRoute != null;
    if (routeVariable != null && !isAppRoute) {
      _error(
        diagnostics,
        file.path,
        'route.dart must initialize route with AppRoute<Params, Search, Data>.',
      );
    }
    final typeArguments = appRoute?.typeArguments;
    final arguments = typeArguments?.arguments;
    if (isAppRoute) {
      if (arguments == null || arguments.length != 3) {
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
    final argumentList = appRoute?.argumentList;
    final argumentNames = argumentList != null
        ? argumentList.arguments
              .whereType<NamedExpression>()
              .map((argument) => argument.name.label.name)
              .toSet()
        : const <String>{};
    final declaresParams = argumentNames.contains('params');
    final declaresSearch = argumentNames.contains('search');
    final declaresDocument = _hasInvocation(initializer, 'document');
    if (argumentNames.contains('document')) {
      _error(
        diagnostics,
        file.path,
        'Document output is an optional capability. Import document.dart and '
        'attach it with `AppRoute(...).document(...)`.',
      );
    }
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
    return RouteContract(
      params: params,
      search: search,
      paramsSchema: paramsSchema,
      searchSchema: searchSchema,
      declaresParams: declaresParams,
      declaresSearch: declaresSearch,
      declaresDocument: declaresDocument,
    );
  }

  void _requireBoundRoute(
    File file,
    String method,
    List<FileRouteDiagnostic> diagnostics,
  ) {
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
    final route = result.unit.declarations
        .whereType<TopLevelVariableDeclaration>()
        .expand((declaration) => declaration.variables.variables)
        .where((variable) => variable.name.lexeme == 'route')
        .firstOrNull;
    if (route == null) {
      _error(
        diagnostics,
        file.path,
        'File must export a top-level variable named route.',
      );
      return;
    }
    final initializer = route.initializer;
    final valid =
        initializer is MethodInvocation &&
        initializer.methodName.name == method &&
        initializer.target?.toSource().endsWith('.route') == true;
    if (!valid) {
      _error(
        diagnostics,
        file.path,
        '${p.basename(file.path)} must bind its sibling declaration with '
        '`final route = definition.route.$method(...)`.',
      );
    }
  }

  ({TypeArgumentList? typeArguments, ArgumentList argumentList})?
  _appRouteCreation(Expression? expression) {
    return switch (expression) {
      InstanceCreationExpression()
          when expression.constructorName.type.name.lexeme == 'AppRoute' =>
        (
          typeArguments: expression.constructorName.type.typeArguments,
          argumentList: expression.argumentList,
        ),
      MethodInvocation(:final methodName) when methodName.name == 'AppRoute' =>
        (
          typeArguments: expression.typeArguments,
          argumentList: expression.argumentList,
        ),
      MethodInvocation(:final target) => _appRouteCreation(target),
      _ => null,
    };
  }

  bool _hasInvocation(Expression? expression, String name) {
    return switch (expression) {
      MethodInvocation(:final target, :final methodName) =>
        methodName.name == name || _hasInvocation(target, name),
      _ => false,
    };
  }

  void _validateTree(
    RouteNode node,
    List<FileRouteDiagnostic> diagnostics,
    List<RouteField> inheritedParams,
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

    final nextParams = <RouteField>[...inheritedParams];
    for (final field in params?.fields ?? const <RouteField>[]) {
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

    final childPaths = <String, RouteNode>{};
    final childMembers = <String, RouteNode>{};
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
    List<RouteNode> nodes,
    List<FileRouteDiagnostic> diagnostics,
  ) {
    final keys = <String, RouteNode>{};
    final terminalPatterns = <String, RouteNode>{};
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

      if (!node.isPageTerminal) continue;
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

  bool _schemaFieldsSupported(List<RouteField> fields, {required bool path}) =>
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

  void _flatten(RouteNode node, List<RouteNode> output) {
    output.add(node);
    for (final child in node.children) {
      _flatten(child, output);
    }
  }

  List<String> _staticRoutes(List<RouteNode> nodes) => nodes
      .where((node) => node.isPageTerminal)
      .map((node) => node.staticLocation)
      .nonNulls
      .toList(growable: false);

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
