import 'dart:async';

import 'codec.dart';
import 'pattern.dart';

/// A route loader.
typedef RouteLoader<P, S, D> =
    FutureOr<D> Function(RouteLoadContext<P, S> context);

/// Typed input passed to a route loader.
final class RouteLoadContext<P, S> {
  /// Creates loader input.
  const RouteLoadContext({
    required this.params,
    required this.search,
    required this.location,
  });

  /// Parameters owned by the route.
  final P params;

  /// Search state owned by the route.
  final S search;

  /// The complete matched location.
  final Uri location;
}

/// Declares loader data supplied by a separate route fragment.
final class RouteData<D> {
  /// Creates a loader-data type witness.
  const RouteData();
}

/// An immutable navigation target.
final class Destination {
  const Destination._({required this.route, required this.uri});

  /// The target route.
  final AnyAppRoute route;

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

/// The erased route interface used by route trees.
abstract class AnyAppRoute {
  /// The route's relative or absolute path declaration.
  String? get path;

  /// Child routes.
  List<AnyAppRoute> get children;

  /// Stable identity shared by compiled route fragments.
  Object get identity;

  /// Whether this route can be the final match for a location.
  bool get terminal;

  /// Whether dynamic path values have a typed codec.
  bool get hasPathCodec;

  /// The parsed path pattern.
  RoutePattern get compiledPattern;

  /// Decodes this route's path parameters.
  Object? decodePath(Map<String, List<String>> values);

  /// Decodes this route's search state.
  DecodedSearch<Object?> decodeQuery(Map<String, List<String>> values);

  /// Runs this route's loader through an erased route-tree boundary.
  FutureOr<Object?> loadObject(Object? params, Object? search, Uri location);
}

/// A typed route definition shared by manual and file routing.
final class AppRoute<P, S, D> implements AnyAppRoute {
  /// Creates a route definition.
  factory AppRoute({
    String? path,
    PathParams<P>? params,
    SearchParams<S>? search,
    RouteData<D>? data,
    RouteLoader<P, S, D>? load,
    bool terminal = true,
    Iterable<AnyAppRoute> children = const <AnyAppRoute>[],
  }) => AppRoute<P, S, D>._(
    path: path,
    params: params,
    search: search,
    data: data,
    load: load,
    terminal: terminal,
    children: children,
    identity: Object(),
  );

  AppRoute._({
    required this.path,
    required this.params,
    required this.search,
    required this.data,
    required this.load,
    required this.terminal,
    required Iterable<AnyAppRoute> children,
    required this.identity,
  }) : children = List<AnyAppRoute>.unmodifiable(children),
       _pattern = path == null ? null : RoutePattern.parse(path);

  @override
  final String? path;

  /// The typed path contract, when the route owns dynamic path segments.
  final PathParams<P>? params;

  /// The typed search contract, when the route owns query state.
  final SearchParams<S>? search;

  /// The data contract for a loader supplied by another fragment.
  final RouteData<D>? data;

  /// The route loader, when it runs in the current application.
  final RouteLoader<P, S, D>? load;

  @override
  final bool terminal;

  @override
  bool get hasPathCodec => params != null;

  @override
  final List<AnyAppRoute> children;

  @override
  final Object identity;

  final RoutePattern? _pattern;

  @override
  RoutePattern get compiledPattern =>
      _pattern ??
      (throw StateError('A file route must be compiled before use.'));

  /// Returns a copy with [children] attached to the same definition.
  AppRoute<P, S, D> withChildren(Iterable<AnyAppRoute> children) =>
      AppRoute<P, S, D>._(
        path: path,
        params: params,
        search: search,
        data: data,
        load: load,
        terminal: terminal,
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
  FutureOr<Object?> loadObject(Object? params, Object? search, Uri location) {
    final loader = load;
    if (loader == null) return const NoData();
    return loader(
      RouteLoadContext<P, S>(
        params: params as P,
        search: search as S,
        location: location,
      ),
    );
  }

  Destination _buildDestination(P params, S? search) {
    final pattern = compiledPattern;
    final encodedPath =
        this.params?.encode(params) ?? const <String, List<String>>{};
    final pathSegments = pattern.build(encodedPath);
    final encodedSearch = search == null
        ? const <String, List<String>>{}
        : this.search?.encode(search) ?? const <String, List<String>>{};
    final uri = Uri(
      pathSegments: <String>['', ...pathSegments],
      queryParameters: encodedSearch.isEmpty ? null : encodedSearch,
    );
    return Destination._(route: this, uri: uri);
  }
}

/// Creates a destination for a route with path parameters.
extension ParameterizedAppRouteDestination<P, S, D> on AppRoute<P, S, D> {
  /// Builds a canonical destination.
  Destination to({required P params, S? search}) =>
      _buildDestination(params, search);
}

/// Creates a destination for a route without path parameters.
extension StaticAppRouteDestination<S, D> on AppRoute<NoParams, S, D> {
  /// Builds a canonical destination.
  Destination to({S? search}) => _buildDestination(const NoParams(), search);
}
