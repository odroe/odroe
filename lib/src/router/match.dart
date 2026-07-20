import 'dart:collection';

import 'package:roux/roux.dart' as roux;

import 'codec.dart';
import 'route.dart';

/// One typed route match.
final class RouteMatch<P, S, D> {
  const RouteMatch._({
    required this.route,
    required this.params,
    required this.search,
    required this.searchError,
    required this.location,
    required this.branch,
  });

  /// The matched route definition.
  final TypedRoute<P, S, D> route;

  /// Path parameters owned by the route.
  final P params;

  /// Search state owned by the route.
  final S search;

  /// A recovered search parsing error.
  final Object? searchError;

  /// The complete matched location.
  final Uri location;

  /// The complete active route branch.
  final RouteBranch branch;
}

final class _MatchedNode {
  const _MatchedNode({
    required this.route,
    required this.params,
    required this.search,
    required this.searchKeys,
    required this.searchError,
    required this.pathEnd,
  });

  final RouteNode route;
  final Object? params;
  final Object? search;
  final Set<String> searchKeys;
  final Object? searchError;
  final int pathEnd;
}

/// The ordered matches for one location.
final class RouteMatches {
  RouteMatches._(this.sourceLocation, this._matches)
    : location = _canonicalize(sourceLocation, _matches),
      routes = List<RouteNode>.unmodifiable(
        _matches.map((match) => match.route),
      ),
      branch = RouteBranch.from(
        _matches.map(
          (match) =>
              (route: match.route, params: match.params, search: match.search),
        ),
      );

  /// The incoming location before typed codecs normalized it.
  final Uri sourceLocation;

  /// The canonical location rebuilt from typed params and search state.
  final Uri location;

  /// Matched route definitions from root to leaf.
  final List<RouteNode> routes;

  /// Typed route values for the active branch.
  final RouteBranch branch;

  final List<_MatchedNode> _matches;

  static Uri _canonicalize(Uri source, List<_MatchedNode> matches) {
    final segments = <String>[];
    final claimedSearchKeys = <String>{};
    for (final match in matches) {
      segments.addAll(match.route.encodePath(match.params));
      claimedSearchKeys.addAll(match.searchKeys);
    }

    final query = <String, List<String>>{};
    for (final entry in source.queryParametersAll.entries) {
      if (!claimedSearchKeys.contains(entry.key)) {
        query[entry.key] = entry.value;
      }
    }
    for (final match in matches) {
      query.addAll(match.route.encodeQuery(match.search));
    }

    return segments.isEmpty
        ? Uri(
            path: '/',
            queryParameters: query.isEmpty ? null : query,
            fragment: source.hasFragment ? source.fragment : null,
          )
        : Uri(
            pathSegments: <String>['', ...segments],
            queryParameters: query.isEmpty ? null : query,
            fragment: source.hasFragment ? source.fragment : null,
          );
  }

  /// The closest terminal ancestor location, if one exists.
  Uri? get parentLocation {
    for (var index = _matches.length - 2; index >= 0; index--) {
      final match = _matches[index];
      if (!match.route.terminal) continue;
      final segments = location.pathSegments.take(match.pathEnd).toList();
      return segments.isEmpty
          ? Uri(
              path: '/',
              queryParameters: location.queryParametersAll.isEmpty
                  ? null
                  : location.queryParametersAll,
            )
          : Uri(
              pathSegments: <String>['', ...segments],
              queryParameters: location.queryParametersAll.isEmpty
                  ? null
                  : location.queryParametersAll,
            );
    }
    return null;
  }

  /// Returns the typed match belonging to [route].
  RouteMatch<P, S, D>? match<P, S, D>(TypedRoute<P, S, D> route) {
    for (final value in _matches) {
      if (!identical(value.route.identity, route.identity)) continue;
      return RouteMatch<P, S, D>._(
        route: route,
        params: value.params as P,
        search: value.search as S,
        searchError: value.searchError,
        location: location,
        branch: branch,
      );
    }
    return null;
  }

  /// Returns the typed leaf match.
  RouteMatch<P, S, D> leaf<P, S, D>(TypedRoute<P, S, D> route) {
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
  /// Creates a matcher backed by Roux.
  RouteMatcher(Iterable<RouteNode> routes) {
    _register(
      routes,
      '/',
      const <RouteNode>[],
      HashSet<Object>.identity(),
      <String>{},
    );
  }

  final roux.Router<_Candidate> _router = roux.Router<_Candidate>(
    caseSensitive: true,
  );

  /// Matches [location], returning `null` when no complete branch matches.
  RouteMatches? match(Uri location) {
    if (!location.hasAbsolutePath) {
      throw ArgumentError.value(
        location,
        'location',
        'Route locations must have an absolute path.',
      );
    }
    final found = _router.find(_pathname(location));
    if (found == null) return null;
    return _decode(location, found.data, found.params);
  }

  RouteMatches? _decode(
    Uri location,
    _Candidate candidate,
    Map<String, String> captures,
  ) {
    final query = location.queryParametersAll;
    final matches = <_MatchedNode>[];
    final claimedSearchKeys = <String>{};
    var pathEnd = 0;
    for (final route in candidate.branch) {
      final template = route.template;
      Object? params;
      try {
        params = route.decodePath(template.captures(captures));
      } on ParameterFormatException {
        return null;
      }
      final search = route.decodeQuery(query);
      Set<String>? overlap;
      for (final key in search.keys) {
        if (claimedSearchKeys.contains(key)) {
          (overlap ??= <String>{}).add(key);
        }
      }
      if (overlap != null) {
        throw StateError(
          'Search parameters $overlap are owned by more than one active route.',
        );
      }
      pathEnd += template.consumedSegments(captures);
      matches.add(
        _MatchedNode(
          route: route,
          params: params,
          search: search.value,
          searchKeys: search.keys,
          searchError: search.error,
          pathEnd: pathEnd,
        ),
      );
      claimedSearchKeys.addAll(search.keys);
    }
    return RouteMatches._(location, List<_MatchedNode>.of(matches));
  }

  void _register(
    Iterable<RouteNode> routes,
    String parentPattern,
    List<RouteNode> parentBranch,
    Set<Object> identities,
    Set<String> patterns,
  ) {
    for (final route in routes) {
      if (!identities.add(route.identity)) {
        throw StateError(
          'A route definition cannot appear more than once in one tree.',
        );
      }
      final dynamicNames = route.template.parameterNames;
      if (dynamicNames.isNotEmpty && !route.hasPathCodec) {
        throw StateError(
          'Route "${route.path}" must declare PathParams for $dynamicNames.',
        );
      }
      final pattern = _join(parentPattern, route.template.pattern);
      final branch = <RouteNode>[...parentBranch, route];
      if (route.terminal) {
        if (!patterns.add(_shape(pattern))) {
          throw StateError('More than one terminal route uses "$pattern".');
        }
        _router.add(pattern, _Candidate(branch));
      }
      _register(route.children, pattern, branch, identities, patterns);
    }
  }

  static String _join(String parent, String child) {
    if (child.isEmpty) return parent;
    return parent == '/' ? '/$child' : '$parent/$child';
  }

  static String _shape(String pattern) => pattern
      .split('/')
      .map((segment) {
        if (segment.startsWith('**:')) return '**';
        if (segment.startsWith(':')) return ':';
        return segment;
      })
      .join('/');

  static String _pathname(Uri location) {
    final segments = location.pathSegments;
    if (segments.isEmpty) return '/';
    return '/${segments.map(Uri.encodeComponent).join('/')}';
  }
}

final class _Candidate {
  _Candidate(List<RouteNode> branch)
    : branch = List<RouteNode>.of(branch, growable: false);

  final List<RouteNode> branch;
}
