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

  /// Whether a write changed either generated output file.
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

/// One directory in the scanned filesystem route tree.
final class RouteNode {
  /// Creates one scanned filesystem route node.
  RouteNode({
    required this.directory,
    required this.segments,
    required this.path,
    required this.routeFile,
    required this.pageFile,
    required this.shellFile,
    required this.serverFile,
  });

  /// Directory represented by this node.
  final Directory directory;

  /// Filesystem segments from the routes root to [directory].
  final List<String> segments;

  /// Filesystem path segment, using `[name]`, `[...name]`, and group syntax.
  final String path;

  /// Optional neutral route declaration.
  final File? routeFile;

  /// Optional Flutter page binding.
  final File? pageFile;

  /// Optional Flutter shell binding.
  final File? shellFile;

  /// Optional server binding.
  final File? serverFile;

  /// Structural child directories.
  final List<RouteNode> children = <RouteNode>[];

  /// Server functions declared in [serverFile].
  final List<ServerFunctionDeclaration> functions =
      <ServerFunctionDeclaration>[];

  /// Imports visible to server-function signatures.
  final List<ServerImport> serverImports = <ServerImport>[];

  /// Whether [serverFile] exposes public HTTP handlers.
  bool serverTerminal = false;

  /// Parsed route contract from [routeFile].
  RouteContract? contract;

  /// Structural parent directory.
  RouteNode? parent;

  /// Whether this node or one of its descendants contributes a route.
  bool get hasContent =>
      routeFile != null ||
      pageFile != null ||
      shellFile != null ||
      serverFile != null ||
      children.isNotEmpty;

  /// Whether this node can terminate the client or document route tree.
  bool get isPageTerminal =>
      pageFile != null || (contract?.declaresDocument ?? false);

  /// Whether this directory owns a runtime route declaration or binding.
  bool get emitsRuntimeRoute =>
      routeFile != null ||
      pageFile != null ||
      shellFile != null ||
      serverFile != null;

  /// Nearest runtime descendants, flattening structural-only directories.
  Iterable<RouteNode> get runtimeChildren sync* {
    for (final child in children) {
      if (child.emitsRuntimeRoute) {
        yield child;
      } else {
        yield* child.runtimeChildren;
      }
    }
  }

  /// Runtime lineage with structural-only directories removed.
  List<RouteNode> get runtimeLineage =>
      lineage.where((node) => node.emitsRuntimeRoute).toList(growable: false);

  /// Local Roux path from the nearest emitted ancestor to this node.
  String get runtimePath {
    if (segments.isEmpty) return '/';
    final parts = <String>[];
    RouteNode? current = this;
    while (current != null) {
      if (!identical(current, this) && current.emitsRuntimeRoute) break;
      final part = current._runtimeSegment;
      if (part.isNotEmpty) parts.add(part);
      current = current.parent;
    }
    return parts.reversed.join('/');
  }

  String get _runtimeSegment {
    if (path.isEmpty || path == '/') return '';
    final rest = RegExp(
      r'^\[\.\.\.([A-Za-z_][A-Za-z0-9_]*)\]$',
    ).firstMatch(path);
    if (rest != null) return '**:${rest.group(1)}';
    final parameter = RegExp(
      r'^\[([A-Za-z_][A-Za-z0-9_]*)\]$',
    ).firstMatch(path);
    if (parameter != null) return ':${parameter.group(1)}';
    return path;
  }

  /// Complete static location, or `null` when the path needs parameters.
  String? get staticLocation {
    final parts = <String>[];
    for (final node in lineage) {
      final part = node.path;
      if (part.startsWith('[')) return null;
      if (part.isNotEmpty && part != '/') parts.add(part);
    }
    return parts.isEmpty ? '/' : '/${parts.join('/')}';
  }

  /// Stable generated identifier suffix.
  String get key => segments.isEmpty
      ? 'Root'
      : segments.map(_identifierPart).map(_upperFirst).join();

  /// Generated client route variable.
  String get variable => '_route$key';

  /// Generated server route variable.
  String get serverVariable => '_serverRoute$key';

  /// Generated typed navigation facade.
  String get className => segments.isEmpty ? 'AppRoutes' : 'App${key}Routes';

  /// Member name under the parent navigation facade.
  String get memberName => segments.isEmpty ? 'root' : _member(segments.last);

  /// Import alias for [routeFile].
  String get routeAlias => '${_snake(key)}_definition';

  /// Import alias for [pageFile].
  String get pageAlias => '${_snake(key)}_page';

  /// Import alias for [shellFile].
  String get shellAlias => '${_snake(key)}_shell';

  /// Import alias for [serverFile].
  String get serverAlias => '${_snake(key)}_server';

  /// Canonical pattern used to detect ambiguous terminal routes.
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

  /// Generated search argument owned by [target].
  String searchArgumentName({required RouteNode target}) =>
      identical(this, target) ? 'search' : '${_lowerFirst(key)}Search';

  /// Structural lineage from the root through this node.
  List<RouteNode> get lineage {
    final values = <RouteNode>[];
    RouteNode? current = this;
    while (current != null) {
      values.add(current);
      current = current.parent;
    }
    return values.reversed.toList(growable: false);
  }

  /// All path fields inherited by this node.
  List<RouteField> get allParams => lineage
      .expand((node) => node.contract?.params?.fields ?? const <RouteField>[])
      .toList(growable: false);

  /// Imports needed by the generated client route tree.
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

  static String _snake(String value) {
    final output = StringBuffer();
    for (var index = 0; index < value.length; index++) {
      final character = value[index];
      if (index > 0 && character != character.toLowerCase()) {
        output.write('_');
      }
      output.write(character.toLowerCase());
    }
    return output.toString();
  }
}

/// A public server function discovered in `server.dart`.
final class ServerFunctionDeclaration {
  /// Creates a server-function declaration.
  const ServerFunctionDeclaration({
    required this.name,
    required this.inputType,
    required this.outputType,
    required this.streamType,
    required this.method,
  });

  /// Top-level variable name.
  final String name;

  /// Client-visible input type.
  final String inputType;

  /// Declared output type.
  final String outputType;

  /// Stream item type when [outputType] is a stream.
  final String? streamType;

  /// Generated HTTP method expression.
  final String method;
}

/// An import declared by a route's `server.dart`.
final class ServerImport {
  /// Creates an import description.
  const ServerImport({required this.uri, required this.prefix});

  /// Import URI.
  final String uri;

  /// Optional source prefix.
  final String? prefix;
}

/// Parsed type and capability declarations from `route.dart`.
final class RouteContract {
  /// Creates a parsed route contract.
  const RouteContract({
    required this.params,
    required this.search,
    required this.paramsSchema,
    required this.searchSchema,
    required this.declaresParams,
    required this.declaresSearch,
    required this.declaresDocument,
  });

  /// Local path-parameter record.
  final RecordContract? params;

  /// Local search-state record.
  final RecordContract? search;

  /// Whether the built-in params schema is requested.
  final bool paramsSchema;

  /// Whether the built-in search schema is requested.
  final bool searchSchema;

  /// Whether `AppRoute` receives a params codec.
  final bool declaresParams;

  /// Whether `AppRoute` receives a search codec.
  final bool declaresSearch;

  /// Whether the declaration attaches the optional document capability.
  final bool declaresDocument;
}

/// One named record contract declared by a route.
final class RecordContract {
  /// Creates a record contract.
  const RecordContract({required this.name, required this.fields});

  /// Typedef name.
  final String name;

  /// Named record fields.
  final List<RouteField> fields;
}

/// One named field in a route record contract.
final class RouteField {
  /// Creates a route field.
  RouteField({required this.name, required this.type});

  /// Field name.
  final String name;

  /// Dart source for the field type.
  final String type;

  /// Route that owns this field after validation.
  RouteNode? owner;
}

/// A generated source import and its required prefix.
final class SourceImport {
  /// Creates a generated source import.
  const SourceImport(this.uri, this.alias);

  /// Project-relative import URI.
  final String uri;

  /// Generated prefix.
  final String alias;
}
