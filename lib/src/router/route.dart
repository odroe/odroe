import 'dart:async';

import '../document/document.dart';
import '../query/client.dart';
import 'codec.dart';
import 'pattern.dart';

/// A route loader.
typedef RouteLoader<P, S, D> =
    FutureOr<D> Function(RouteLoadContext<P, S> context);

/// Builds the semantic document contribution owned by one matched route.
typedef RouteDocumentBuilder<P, S, D> =
    FutureOr<RouteDocument?> Function(RouteDocumentContext<P, S, D> context);

/// Typed params and search belonging to one active route.
final class RouteValues<P, S> {
  const RouteValues._({required this.params, required this.search});

  /// Path parameters owned by the route.
  final P params;

  /// Search state owned by the route.
  final S search;
}

final class _RouteBranchEntry {
  const _RouteBranchEntry({
    required this.route,
    required this.params,
    required this.search,
    required this.data,
  });

  final RouteNode route;
  final Object? params;
  final Object? search;
  final Object? data;
}

/// The active route branch shared by loaders and document builders.
final class RouteBranch {
  /// Creates branch state from ordered matched route values.
  RouteBranch.from(
    Iterable<({RouteNode route, Object? params, Object? search, Object? data})>
    values,
  ) : _entries = <_RouteBranchEntry>[
        for (final value in values)
          _RouteBranchEntry(
            route: value.route,
            params: value.params,
            search: value.search,
            data: value.data,
          ),
      ];

  final List<_RouteBranchEntry> _entries;

  _RouteBranchEntry? _find(RouteNode route) {
    for (final entry in _entries) {
      if (identical(entry.route.identity, route.identity)) return entry;
    }
    return null;
  }

  RouteValues<P, S>? _match<P, S, D>(TypedRoute<P, S, D> route) {
    final value = _find(route);
    if (value == null) return null;
    return RouteValues<P, S>._(
      params: value.params as P,
      search: value.search as S,
    );
  }

  RouteDocumentValues<P, S, D>? _matchDocument<P, S, D>(
    TypedRoute<P, S, D> route,
  ) {
    final value = _find(route);
    if (value == null) return null;
    return RouteDocumentValues<P, S, D>._(
      params: value.params as P,
      search: value.search as S,
      data: value.data as D,
    );
  }
}

/// Typed input passed to a route loader.
final class RouteLoadContext<P, S> {
  /// Creates loader input.
  RouteLoadContext({
    required this.params,
    required this.search,
    required this.location,
    QueryClient? query,
    required RouteBranch branch,
  }) : query = query ?? QueryClient(),
       _branch = branch;

  /// Parameters owned by the route.
  final P params;

  /// Search state owned by the route.
  final S search;

  /// The complete matched location.
  final Uri location;

  /// Query client shared by every loader in the matched branch.
  final QueryClient query;

  final RouteBranch _branch;

  /// Returns typed values for an active ancestor or current route.
  RouteValues<ParentP, ParentS>? match<ParentP, ParentS, ParentD>(
    TypedRoute<ParentP, ParentS, ParentD> route,
  ) => _branch._match(route);
}

/// Typed values and loader data belonging to one active route document.
final class RouteDocumentValues<P, S, D> {
  const RouteDocumentValues._({
    required this.params,
    required this.search,
    required this.data,
  });

  /// Path parameters owned by the route.
  final P params;

  /// Search state owned by the route.
  final S search;

  /// Loader data owned by the route.
  final D data;
}

/// Typed input passed to a route's semantic document builder.
final class RouteDocumentContext<P, S, D> {
  /// Creates document builder input.
  const RouteDocumentContext({
    required this.params,
    required this.search,
    required this.data,
    required this.location,
    required RouteBranch branch,
  }) : _branch = branch;

  /// Parameters owned by the route.
  final P params;

  /// Search state owned by the route.
  final S search;

  /// Loader data owned by the route.
  final D data;

  /// The complete matched location.
  final Uri location;

  final RouteBranch _branch;

  /// Returns typed values for any route in the active matched branch.
  RouteDocumentValues<MatchP, MatchS, MatchD>? match<MatchP, MatchS, MatchD>(
    TypedRoute<MatchP, MatchS, MatchD> route,
  ) => _branch._matchDocument(route);
}

/// An immutable navigation target.
final class Destination {
  const Destination._({required this.route, required this.uri});

  /// Creates a destination for a custom or generated route reference.
  factory Destination.forRoute({required RouteNode route, required Uri uri}) {
    if (!uri.hasAbsolutePath) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Destination path must be absolute.',
      );
    }
    return Destination._(route: route, uri: uri);
  }

  /// The target route.
  final RouteNode route;

  /// The canonical target URI.
  final Uri uri;

  @override
  bool operator ==(Object other) =>
      other is Destination &&
      identical(route.identity, other.route.identity) &&
      uri == other.uri;

  @override
  int get hashCode => Object.hash(identityHashCode(route.identity), uri);

  @override
  String toString() => uri.toString();
}

/// A node stored in a route tree.
abstract class RouteNode {
  /// The route's relative or absolute path declaration.
  String? get path;

  /// Child routes.
  List<RouteNode> get children;

  /// Stable identity shared by compiled route variants.
  Object get identity;

  /// Whether this route can be the final match for a location.
  bool get terminal;

  /// Whether dynamic path values have a typed codec.
  bool get hasPathCodec;

  /// Whether this route contributes a semantic HTML document.
  bool get hasDocument;

  /// Whether this route can render a terminal Flutter page.
  bool get hasFlutterPage;

  /// The parsed path pattern.
  RoutePattern get compiledPattern;

  /// Decodes this route's path parameters.
  Object? decodePath(Map<String, List<String>> values);

  /// Decodes this route's search state.
  DecodedSearch<Object?> decodeQuery(Map<String, List<String>> values);

  /// Runs this route's loader through the route-tree boundary.
  FutureOr<Object?> loadObject(
    Object? params,
    Object? search,
    Uri location,
    RouteBranch branch,
    QueryClient query,
  );

  /// Builds this route's document through the route-tree boundary.
  FutureOr<RouteDocument?> buildDocumentObject(
    Object? params,
    Object? search,
    Object? data,
    Uri location,
    RouteBranch branch,
  );

  /// Encodes this route's local path through the generated boundary.
  List<String> encodePath(Object? params);

  /// Encodes this route's local search state.
  Map<String, List<String>> encodeQuery(Object? search);
}

/// A route whose local params and search types are known at compile time.
abstract class TypedRoute<P, S, D> implements RouteNode {}

abstract interface class _RouteRefSegment {
  RouteNode get routeNode;
  List<String> buildPath();
  Map<String, List<String>> buildQuery();
}

/// One strongly typed, locally bound route reference.
final class RouteRef<P, S, D> implements _RouteRefSegment {
  const RouteRef._({required this.route, required this.params, this.search});

  /// The referenced route.
  final TypedRoute<P, S, D> route;

  /// Path parameters owned by this route.
  final P params;

  /// Search state owned by this route, or its canonical defaults when absent.
  final S? search;

  @override
  RouteNode get routeNode => route;

  @override
  List<String> buildPath() => route.encodePath(params);

  @override
  Map<String, List<String>> buildQuery() => route.encodeQuery(search);

  /// Appends [child] to this manual or generated route branch.
  RouteRefPath then<ChildP, ChildS, ChildD>(
    RouteRef<ChildP, ChildS, ChildD> child,
  ) => RouteRefPath._(<_RouteRefSegment>[this, child]);

  /// Builds a destination containing only this route reference.
  Destination get destination =>
      RouteRefPath._(<_RouteRefSegment>[this]).destination;
}

/// An ordered branch of strongly typed route references.
final class RouteRefPath {
  RouteRefPath._(List<_RouteRefSegment> refs)
    : _refs = List<_RouteRefSegment>.unmodifiable(refs);

  final List<_RouteRefSegment> _refs;

  /// Appends [child] to this branch.
  RouteRefPath then<P, S, D>(RouteRef<P, S, D> child) =>
      RouteRefPath._(<_RouteRefSegment>[..._refs, child]);

  /// Encodes this complete branch into one canonical destination.
  Destination get destination {
    final segments = <String>[];
    final query = <String, List<String>>{};
    for (final ref in _refs) {
      segments.addAll(ref.buildPath());
      for (final entry in ref.buildQuery().entries) {
        if (query.containsKey(entry.key)) {
          throw StateError(
            'Search parameter "${entry.key}" is encoded by more than one '
            'route reference.',
          );
        }
        query[entry.key] = entry.value;
      }
    }
    final target = _refs.last.routeNode;
    if (!target.terminal) {
      throw StateError('A destination must end at a terminal route.');
    }
    return Destination._(
      route: target,
      uri: segments.isEmpty
          ? Uri(path: '/', queryParameters: query.isEmpty ? null : query)
          : Uri(
              pathSegments: <String>['', ...segments],
              queryParameters: query.isEmpty ? null : query,
            ),
    );
  }
}

/// A typed route definition shared by manual and file routing.
final class AppRoute<P, S, D> implements TypedRoute<P, S, D> {
  /// Creates a route definition.
  factory AppRoute({
    String? path,
    PathParams<P>? params,
    SearchParams<S>? search,
    RouteLoader<P, S, D>? load,
    RouteDocumentBuilder<P, S, D>? document,
    bool terminal = true,
    Iterable<RouteNode> children = const <RouteNode>[],
  }) => AppRoute<P, S, D>._(
    path: path,
    params: params,
    search: search,
    load: load,
    document: document,
    terminal: terminal,
    hasFlutterPage: false,
    children: children,
    identity: Object(),
  );

  AppRoute._({
    required this.path,
    required this.params,
    required this.search,
    required this.load,
    required this.document,
    required this.terminal,
    required bool hasFlutterPage,
    required Iterable<RouteNode> children,
    required this.identity,
  }) : children = List<RouteNode>.unmodifiable(children),
       _hasFlutterPage = hasFlutterPage,
       _pattern = path == null ? null : RoutePattern.parse(path);

  @override
  final String? path;

  /// The typed path contract, when the route owns dynamic path segments.
  final PathParams<P>? params;

  /// The typed search contract, when the route owns query state.
  final SearchParams<S>? search;

  /// The route loader, when it runs in the current application.
  final RouteLoader<P, S, D>? load;

  /// Semantic HTML produced for SSR, SSG, SEO, and GEO.
  final RouteDocumentBuilder<P, S, D>? document;

  @override
  final bool terminal;

  @override
  bool get hasPathCodec => params != null;

  @override
  bool get hasDocument => document != null;

  @override
  bool get hasFlutterPage => _hasFlutterPage;

  final bool _hasFlutterPage;

  @override
  final List<RouteNode> children;

  @override
  final Object identity;

  final RoutePattern? _pattern;

  @override
  RoutePattern get compiledPattern =>
      _pattern ??
      (throw StateError('A file route must be compiled before use.'));

  /// Returns a copy with [children] attached to the same definition.
  AppRoute<P, S, D> withChildren(Iterable<RouteNode> children) =>
      AppRoute<P, S, D>._(
        path: path,
        params: params,
        search: search,
        load: load,
        document: document,
        terminal: terminal,
        hasFlutterPage: _hasFlutterPage,
        children: children,
        identity: identity,
      );

  /// Binds a file-system path and generated codecs to this definition.
  AppRoute<P, S, D> compiled({
    required String path,
    PathParams<P>? params,
    SearchParams<S>? search,
    required bool terminal,
    bool? hasFlutterPage,
    Iterable<RouteNode> children = const <RouteNode>[],
  }) => AppRoute<P, S, D>._(
    path: path,
    params: params ?? this.params,
    search: search ?? this.search,
    load: load,
    document: document,
    terminal: terminal,
    hasFlutterPage: hasFlutterPage ?? _hasFlutterPage,
    children: children,
    identity: identity,
  );

  @override
  Object? decodePath(Map<String, List<String>> values) {
    final codec = params;
    if (codec == null) {
      if (values.isNotEmpty) {
        throw ParameterFormatException(
          'Route "$path" declares dynamic segments without PathParams.',
        );
      }
      return const NoParams();
    }
    return codec.decode(values);
  }

  @override
  DecodedSearch<Object?> decodeQuery(Map<String, List<String>> values) {
    final codec = search;
    if (codec == null) {
      return const DecodedSearch<Object?>(value: NoSearch(), keys: <String>{});
    }
    final result = codec.decode(values);
    return DecodedSearch<Object?>(
      value: result.value,
      keys: result.keys,
      error: result.error,
    );
  }

  @override
  FutureOr<Object?> loadObject(
    Object? params,
    Object? search,
    Uri location,
    RouteBranch branch,
    QueryClient query,
  ) {
    final loader = load;
    if (loader == null) return const NoData();
    return loader(
      RouteLoadContext<P, S>(
        params: params as P,
        search: search as S,
        location: location,
        query: query,
        branch: branch,
      ),
    );
  }

  @override
  FutureOr<RouteDocument?> buildDocumentObject(
    Object? params,
    Object? search,
    Object? data,
    Uri location,
    RouteBranch branch,
  ) {
    final builder = document;
    if (builder == null) return null;
    return builder(
      RouteDocumentContext<P, S, D>(
        params: params as P,
        search: search as S,
        data: data as D,
        location: location,
        branch: branch,
      ),
    );
  }

  @override
  List<String> encodePath(Object? params) {
    final encoded = this.params == null
        ? const <String, List<String>>{}
        : this.params!.encode(params as P);
    return compiledPattern.build(encoded);
  }

  @override
  Map<String, List<String>> encodeQuery(Object? search) {
    if (search == null || this.search == null) {
      return const <String, List<String>>{};
    }
    return this.search!.encode(search as S);
  }
}

/// Binds params and search to a typed route.
extension ParameterizedRouteReference<P, S, D> on TypedRoute<P, S, D> {
  /// Creates a local route reference.
  RouteRef<P, S, D> ref({required P params, S? search}) =>
      RouteRef<P, S, D>._(route: this, params: params, search: search);

  /// Builds a destination containing only this route.
  Destination to({required P params, S? search}) =>
      ref(params: params, search: search).destination;
}

/// Binds search to a typed route without path parameters.
extension StaticRouteReference<S, D> on TypedRoute<NoParams, S, D> {
  /// Creates a local route reference.
  RouteRef<NoParams, S, D> ref({S? search}) => RouteRef<NoParams, S, D>._(
    route: this,
    params: const NoParams(),
    search: search,
  );

  /// Builds a destination containing only this route.
  Destination to({S? search}) => ref(search: search).destination;
}
