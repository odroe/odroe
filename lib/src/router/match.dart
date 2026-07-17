import 'dart:async';

import 'codec.dart';
import 'pattern.dart';
import 'route.dart';

/// One typed route match.
final class RouteMatch<P, S, D> {
  const RouteMatch._({
    required this.route,
    required this.params,
    required this.search,
    required this.searchError,
    required this.location,
  });

  /// The matched route definition.
  final AppRoute<P, S, D> route;

  /// Path parameters owned by the route.
  final P params;

  /// Search state owned by the route.
  final S search;

  /// A recovered search parsing error.
  final Object? searchError;

  /// The complete matched location.
  final Uri location;

  /// Runs the route loader.
  Future<D> load() async {
    final value = await route.loadObject(params, search, location);
    return value as D;
  }
}

final class _ErasedMatch {
  const _ErasedMatch({
    required this.route,
    required this.params,
    required this.search,
    required this.searchKeys,
    required this.searchError,
  });

  final AnyAppRoute route;
  final Object? params;
  final Object? search;
  final Set<String> searchKeys;
  final Object? searchError;
}

/// The ordered matches for one location.
final class RouteMatches {
  const RouteMatches._(this.location, this._matches);

  /// The matched location.
  final Uri location;

  final List<_ErasedMatch> _matches;

  /// Matched route definitions from root to leaf.
  List<AnyAppRoute> get routes =>
      List<AnyAppRoute>.unmodifiable(_matches.map((match) => match.route));

  /// Returns the typed match belonging to [route].
  RouteMatch<P, S, D>? match<P, S, D>(AppRoute<P, S, D> route) {
    for (final value in _matches) {
      if (identical(value.route.identity, route.identity)) {
        return RouteMatch<P, S, D>._(
          route: route,
          params: value.params as P,
          search: value.search as S,
          searchError: value.searchError,
          location: location,
        );
      }
    }
    return null;
  }

  /// Returns the typed leaf match.
  RouteMatch<P, S, D> leaf<P, S, D>(AppRoute<P, S, D> route) {
    final value = match(route);
    if (value == null ||
        !identical(_matches.last.route.identity, route.identity)) {
      throw StateError('The supplied route is not the leaf match.');
    }
    return value;
  }
}

/// Matches locations against an immutable route tree.
final class RouteMatcher {
  /// Creates a matcher and validates route patterns eagerly.
  RouteMatcher(Iterable<AnyAppRoute> routes)
    : _routes = _sort(List<AnyAppRoute>.unmodifiable(routes)) {
    _validate(_routes);
  }

  final List<AnyAppRoute> _routes;

  /// Matches [location], returning `null` when no complete branch matches.
  RouteMatches? match(Uri location) {
    final segments = location.pathSegments;
    final query = location.queryParametersAll;
    final result = _matchLevel(
      routes: _routes,
      segments: segments,
      query: query,
      index: 0,
      claimedSearchKeys: const <String>{},
    );
    if (result == null) return null;
    return RouteMatches._(location, List<_ErasedMatch>.unmodifiable(result));
  }

  List<_ErasedMatch>? _matchLevel({
    required List<AnyAppRoute> routes,
    required List<String> segments,
    required Map<String, List<String>> query,
    required int index,
    required Set<String> claimedSearchKeys,
  }) {
    for (final route in routes) {
      final patternMatch = route.compiledPattern.match(segments, index);
      if (patternMatch == null) continue;

      Object? params;
      try {
        params = route.decodePath(patternMatch.parameters);
      } on ParameterFormatException {
        continue;
      }
      final search = route.decodeQuery(query);

      final overlap = claimedSearchKeys.intersection(search.keys);
      if (overlap.isNotEmpty) {
        throw StateError(
          'Search parameters $overlap are owned by more than one active route.',
        );
      }
      final nextClaimedKeys = <String>{...claimedSearchKeys, ...search.keys};
      final current = _ErasedMatch(
        route: route,
        params: params,
        search: search.value,
        searchKeys: search.keys,
        searchError: search.error,
      );

      if (patternMatch.nextIndex == segments.length && route.terminal) {
        return <_ErasedMatch>[current];
      }

      final childResult = _matchLevel(
        routes: _sort(route.children),
        segments: segments,
        query: query,
        index: patternMatch.nextIndex,
        claimedSearchKeys: nextClaimedKeys,
      );
      if (childResult != null) {
        return <_ErasedMatch>[current, ...childResult];
      }
    }
    return null;
  }

  static List<AnyAppRoute> _sort(Iterable<AnyAppRoute> routes) {
    final result = routes.toList(growable: false);
    result.sort(
      (left, right) =>
          compareRoutePatterns(left.compiledPattern, right.compiledPattern),
    );
    return result;
  }

  static void _validate(List<AnyAppRoute> routes) {
    for (final route in routes) {
      final dynamicNames = route.compiledPattern.parameterNames;
      if (dynamicNames.isNotEmpty &&
          route is AppRoute<Object?, Object?, Object?> &&
          route.params == null) {
        throw StateError(
          'Route "${route.path}" must declare PathParams for $dynamicNames.',
        );
      }
      _validate(route.children);
    }
  }
}
