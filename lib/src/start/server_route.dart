import 'dart:async';

import '../router/route.dart';

/// Server-only behavior attached to a client-safe route definition.
final class ServerRouteFragment<P, S, D> {
  const ServerRouteFragment._({
    required this.definition,
    required this.load,
    required this.middleware,
  });

  /// The shared route contract.
  final AppRoute<P, S, D> definition;

  /// The server loader implementation.
  final RouteLoader<P, S, D> load;

  /// Server middleware declarations interpreted by Start.
  final List<Object> middleware;
}

/// Attaches server-only behavior to an app route.
extension AppRouteServer<P, S, D> on AppRoute<P, S, D> {
  /// Creates a server route fragment.
  ServerRouteFragment<P, S, D> server({
    required FutureOr<D> Function(RouteLoadContext<P, S> context) load,
    Iterable<Object> middleware = const <Object>[],
  }) => ServerRouteFragment<P, S, D>._(
    definition: this,
    load: load,
    middleware: List<Object>.unmodifiable(middleware),
  );
}
