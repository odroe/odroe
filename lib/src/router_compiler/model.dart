// ignore_for_file: public_member_api_docs

import 'dart:io';

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

/// The result of compiling a routes directory.
final class FileRouteOutput {
  /// Creates compiler output.
  const FileRouteOutput({
    required this.source,
    required this.serverSource,
    required this.diagnostics,
    required this.routeCount,
    required this.staticRoutes,
    required this.hasFlutter,
    this.changed = false,
  });

  /// Generated Dart source.
  final String source;

  /// Generated server-only route tree and function manifest.
  final String serverSource;

  /// Diagnostics collected without throwing.
  final List<FileRouteDiagnostic> diagnostics;

  /// Number of route nodes in the generated tree.
  final int routeCount;

  /// Static terminal locations that can be prerendered without input data.
  final List<String> staticRoutes;

  /// Whether the file-route tree contains any Flutter page or shell.
  final bool hasFlutter;

  /// Whether [FileRouteOutput.changed] changed the output file.
  final bool changed;

  /// Whether any fatal diagnostic was produced.
  bool get hasErrors => diagnostics.any(
    (diagnostic) => diagnostic.severity == FileRouteDiagnosticSeverity.error,
  );
}

/// Thrown when a file-route tree contains compilation errors.
final class FileRouteCompilationException implements Exception {
  /// Creates a compilation failure.
  const FileRouteCompilationException(this.diagnostics);

  /// Fatal and non-fatal diagnostics from the attempted compilation.
  final List<FileRouteDiagnostic> diagnostics;

  @override
  String toString() => diagnostics.join('\n');
}

final class RouteNode {
  RouteNode({
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
  final List<RouteNode> children = <RouteNode>[];
  final List<ServerFunctionDeclaration> functions =
      <ServerFunctionDeclaration>[];
  final List<ServerImport> serverImports = <ServerImport>[];
  bool serverTerminal = false;
  RouteContract? contract;
  RouteNode? parent;

  bool get hasContent =>
      routeFile != null ||
      pageFile != null ||
      shellFile != null ||
      serverFile != null ||
      children.isNotEmpty;

  bool get isPageTerminal =>
      pageFile != null || (contract?.declaresDocument ?? false);

  String? get staticLocation {
    final parts = <String>[];
    for (final node in lineage) {
      final part = node.path;
      if (part.startsWith('[')) return null;
      if (part.isNotEmpty && part != '/') parts.add(part);
    }
    return parts.isEmpty ? '/' : '/${parts.join('/')}';
  }

  String get key => segments.isEmpty
      ? 'Root'
      : segments.map(_identifierPart).map(_upperFirst).join();

  String get variable => '_route$key';
  String get serverVariable => '_serverRoute$key';
  String get className => segments.isEmpty ? 'AppRoutes' : 'App${key}Routes';
  String get memberName => segments.isEmpty ? 'root' : _member(segments.last);
  String get routeAlias => '_${_lowerFirst(key)}Definition';
  String get pageAlias => '_${_lowerFirst(key)}Page';
  String get shellAlias => '_${_lowerFirst(key)}Shell';
  String get serverAlias => '_${_lowerFirst(key)}Server';

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

  String searchArgumentName({required RouteNode target}) =>
      identical(this, target) ? 'search' : '${_lowerFirst(key)}Search';

  List<RouteNode> get lineage {
    final values = <RouteNode>[];
    RouteNode? current = this;
    while (current != null) {
      values.add(current);
      current = current.parent;
    }
    return values.reversed.toList(growable: false);
  }

  List<RouteField> get allParams => lineage
      .expand((node) => node.contract?.params?.fields ?? const <RouteField>[])
      .toList(growable: false);

  Iterable<SourceImport> imports(String from) sync* {
    final needsDefinition =
        pageFile == null && shellFile == null ||
        contract?.params != null ||
        contract?.search != null;
    if (routeFile case final file? when needsDefinition) {
      yield SourceImport(_importUri(file, from), routeAlias);
    }
    if (pageFile case final file?) {
      yield SourceImport(_importUri(file, from), pageAlias);
    }
    if (shellFile case final file?) {
      yield SourceImport(_importUri(file, from), shellAlias);
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

final class ServerFunctionDeclaration {
  const ServerFunctionDeclaration({
    required this.name,
    required this.inputType,
    required this.outputType,
    required this.streamType,
    required this.method,
  });

  final String name;
  final String inputType;
  final String outputType;
  final String? streamType;
  final String method;
}

final class ServerImport {
  const ServerImport({required this.uri, required this.prefix});

  final String uri;
  final String? prefix;
}

final class RouteContract {
  const RouteContract({
    required this.params,
    required this.search,
    required this.paramsSchema,
    required this.searchSchema,
    required this.declaresParams,
    required this.declaresSearch,
    required this.declaresDocument,
  });

  final RecordContract? params;
  final RecordContract? search;
  final bool paramsSchema;
  final bool searchSchema;
  final bool declaresParams;
  final bool declaresSearch;
  final bool declaresDocument;
}

final class RecordContract {
  const RecordContract({required this.name, required this.fields});

  final String name;
  final List<RouteField> fields;
}

final class RouteField {
  RouteField({required this.name, required this.type});

  final String name;
  final String type;
  RouteNode? owner;
}

final class SourceImport {
  const SourceImport(this.uri, this.alias);

  final String uri;
  final String alias;
}
