import 'codec.dart';
import 'path.dart';

/// Descriptive route information shared by every runtime.
final class RouteMetadata {
  /// Creates route metadata.
  const RouteMetadata({
    this.title,
    this.description,
    this.canonical,
    this.values = const <String, Object?>{},
  });

  /// Human-readable title for the route.
  final String? title;

  /// Human-readable summary for the route.
  final String? description;

  /// Canonical location, when it differs from the matched location.
  final String? canonical;

  /// Application-specific metadata.
  final Map<String, Object?> values;
}

/// A typed key used by optional packages to extend a route definition.
final class RouteCapability<T extends Object> {
  /// Creates a capability key with a diagnostic [name].
  const RouteCapability(this.name);

  /// The name shown in diagnostics.
  final String name;

  @override
  String toString() => 'RouteCapability<$T>($name)';
}

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
  });

  final RouteNode route;
  final Object? params;
  final Object? search;
}

/// The matched root-to-leaf route branch.
final class RouteBranch {
  /// Creates branch state from ordered matched values.
  RouteBranch.from(
    Iterable<({RouteNode route, Object? params, Object? search})> values,
  ) : _entries = <_RouteBranchEntry>[
        for (final value in values)
          _RouteBranchEntry(
            route: value.route,
            params: value.params,
            search: value.search,
          ),
      ];

  final List<_RouteBranchEntry> _entries;

  /// Returns untyped values for a route node.
  RouteValues<Object?, Object?>? values(RouteNode route) {
    for (final entry in _entries) {
      if (!identical(entry.route.identity, route.identity)) continue;
      return RouteValues<Object?, Object?>._(
        params: entry.params,
        search: entry.search,
      );
    }
    return null;
  }

  /// Returns typed values for an active route.
  RouteValues<P, S>? match<P, S, D>(TypedRoute<P, S, D> route) {
    final value = values(route);
    if (value == null) return null;
    return RouteValues<P, S>._(
      params: value.params as P,
      search: value.search as S,
    );
  }
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
abstract interface class RouteNode {
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

  /// Metadata shared by optional route capabilities.
  RouteMetadata get metadata;

  /// The parsed path template.
  PathTemplate get template;

  /// Reads an optional capability attached by another package entrypoint.
  T? capability<T extends Object>(RouteCapability<T> key);

  /// Decodes this route's path parameters.
  Object? decodePath(Map<String, List<String>> values);

  /// Decodes this route's search state.
  DecodedSearch<Object?> decodeQuery(Map<String, List<String>> values);

  /// Encodes this route's local path through the generated boundary.
  List<String> encodePath(Object? params);

  /// Encodes this route's local search state.
  Map<String, List<String>> encodeQuery(Object? search);
}

/// A route whose local params, search, and data types are known.
abstract interface class TypedRoute<P, S, D> implements RouteNode {}

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
    RouteMetadata metadata = const RouteMetadata(),
    bool terminal = true,
    Iterable<RouteNode> children = const <RouteNode>[],
  }) => AppRoute<P, S, D>._(
    path: path,
    params: params,
    search: search,
    metadata: metadata,
    terminal: terminal,
    children: children,
    identity: Object(),
    capabilities: const <Object, Object>{},
  );

  AppRoute._({
    required this.path,
    required this.params,
    required this.search,
    required this.metadata,
    required this.terminal,
    required Iterable<RouteNode> children,
    required this.identity,
    required Map<Object, Object> capabilities,
  }) : children = List<RouteNode>.unmodifiable(children),
       _capabilities = Map<Object, Object>.unmodifiable(capabilities),
       _template = path == null ? null : PathTemplate.parse(path);

  @override
  final String? path;

  /// The typed path contract, when the route owns dynamic path segments.
  final PathParams<P>? params;

  /// The typed search contract, when the route owns query state.
  final SearchParams<S>? search;

  @override
  final RouteMetadata metadata;

  @override
  final bool terminal;

  @override
  bool get hasPathCodec => params != null;

  @override
  final List<RouteNode> children;

  @override
  final Object identity;

  final Map<Object, Object> _capabilities;
  final PathTemplate? _template;

  @override
  PathTemplate get template =>
      _template ??
      (throw StateError('A file route must be compiled before use.'));

  @override
  T? capability<T extends Object>(RouteCapability<T> key) =>
      _capabilities[key] as T?;

  /// Returns a copy carrying [value] under [key].
  AppRoute<P, S, D> withCapability<T extends Object>(
    RouteCapability<T> key,
    T value,
  ) => AppRoute<P, S, D>._(
    path: path,
    params: params,
    search: search,
    metadata: metadata,
    terminal: terminal,
    children: children,
    identity: identity,
    capabilities: <Object, Object>{..._capabilities, key: value},
  );

  /// Returns a copy with [children] attached to the same definition.
  AppRoute<P, S, D> withChildren(Iterable<RouteNode> children) =>
      AppRoute<P, S, D>._(
        path: path,
        params: params,
        search: search,
        metadata: metadata,
        terminal: terminal,
        children: children,
        identity: identity,
        capabilities: _capabilities,
      );

  /// Binds a file-system path and generated codecs to this definition.
  AppRoute<P, S, D> compiled({
    required String path,
    PathParams<P>? params,
    SearchParams<S>? search,
    required bool terminal,
    Iterable<RouteNode> children = const <RouteNode>[],
  }) => AppRoute<P, S, D>._(
    path: path,
    params: params ?? this.params,
    search: search ?? this.search,
    metadata: metadata,
    terminal: terminal,
    children: children,
    identity: identity,
    capabilities: _capabilities,
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
  List<String> encodePath(Object? params) {
    final encoded = this.params == null
        ? const <String, List<String>>{}
        : this.params!.encode(params as P);
    return template.build(encoded);
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
