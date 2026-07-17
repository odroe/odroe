import 'dart:async';

import '../query/client.dart';
import '../router/codec.dart';
import '../router/match.dart';
import '../router/pattern.dart';
import '../router/route.dart';
import 'context.dart';
import 'middleware.dart';
import 'request.dart';

/// Typed input for one public HTTP route handler.
final class ServerRouteContext<P, S> {
  const ServerRouteContext({
    required this.request,
    required this.params,
    required this.search,
    required this.location,
  });

  final StartRequestContext request;
  final P params;
  final S search;
  final Uri location;
}

typedef ServerRouteHandler<P, S> =
    FutureOr<StartResponse> Function(ServerRouteContext<P, S> context);

/// Erased server route used by Start's request dispatcher.
abstract interface class AnyServerRoute implements AnyAppRoute {
  List<StartMiddleware> get serverMiddleware;
  bool handles(StartMethod method);
  Future<StartResponse>? handle(
    StartMethod method,
    StartRequestContext request,
    RouteMatches matches,
  );
}

/// Server-only behavior attached to a client-safe route definition.
final class ServerRouteFragment<P, S, D>
    implements TypedAppRoute<P, S, D>, AnyServerRoute {
  ServerRouteFragment._({
    required this.definition,
    required this.load,
    required this.serverMiddleware,
    required this.handlers,
  });

  /// The shared route contract.
  final AppRoute<P, S, D> definition;

  /// Optional server loader implementation.
  final RouteLoader<P, S, D>? load;

  @override
  final List<StartMiddleware> serverMiddleware;

  /// Public HTTP handlers keyed by method.
  final Map<StartMethod, ServerRouteHandler<P, S>> handlers;

  @override
  List<AnyAppRoute> get children => definition.children;

  @override
  RoutePattern get compiledPattern => definition.compiledPattern;

  @override
  bool get hasPathCodec => definition.hasPathCodec;

  @override
  Object get identity => definition.identity;

  @override
  String? get path => definition.path;

  @override
  bool get terminal => definition.terminal;

  @override
  Object? decodePath(Map<String, List<String>> values) =>
      definition.decodePath(values);

  @override
  DecodedSearch<Object?> decodeQuery(Map<String, List<String>> values) =>
      definition.decodeQuery(values);

  @override
  FutureOr<Object?> loadObject(
    Object? params,
    Object? search,
    Uri location,
    RouteLoadScope scope,
    QueryClient query,
  ) {
    final loader = load;
    if (loader == null) {
      return definition.loadObject(params, search, location, scope, query);
    }
    return loader(
      RouteLoadContext<P, S>(
        params: params as P,
        search: search as S,
        location: location,
        query: query,
        scope: scope,
      ),
    );
  }

  @override
  List<String> encodePath(Object? params) => definition.encodePath(params);

  @override
  Map<String, List<String>> encodeQuery(Object? search) =>
      definition.encodeQuery(search);

  @override
  bool handles(StartMethod method) =>
      handlers.containsKey(method) ||
      (method == StartMethod.head && handlers.containsKey(StartMethod.get));

  @override
  Future<StartResponse>? handle(
    StartMethod method,
    StartRequestContext request,
    RouteMatches matches,
  ) {
    final handler =
        handlers[method] ??
        (method == StartMethod.head ? handlers[StartMethod.get] : null);
    if (handler == null) return null;
    final match = matches.match(definition)!;
    return Future<StartResponse>.sync(
      () => handler(
        ServerRouteContext<P, S>(
          request: request,
          params: match.params,
          search: match.search,
          location: match.location,
        ),
      ),
    );
  }

  /// Returns a copy with [children] attached to the shared identity.
  ServerRouteFragment<P, S, D> withChildren(Iterable<AnyAppRoute> children) =>
      ServerRouteFragment<P, S, D>._(
        definition: definition.withChildren(children),
        load: load,
        serverMiddleware: serverMiddleware,
        handlers: handlers,
      );

  /// Binds generated file-system path information.
  ServerRouteFragment<P, S, D> compiled({
    required String path,
    PathParams<P>? params,
    SearchParams<S>? search,
    required bool terminal,
    Iterable<AnyAppRoute> children = const <AnyAppRoute>[],
  }) => ServerRouteFragment<P, S, D>._(
    definition: definition.compiled(
      path: path,
      params: params,
      search: search,
      terminal: terminal,
      children: children,
    ),
    load: load,
    serverMiddleware: serverMiddleware,
    handlers: handlers,
  );
}

/// Attaches server-only behavior to an app route.
extension AppRouteServer<P, S, D> on AppRoute<P, S, D> {
  ServerRouteFragment<P, S, D> server({
    RouteLoader<P, S, D>? load,
    Iterable<StartMiddleware> middleware = const <StartMiddleware>[],
    Map<StartMethod, ServerRouteHandler<P, S>>? handlers,
  }) => ServerRouteFragment<P, S, D>._(
    definition: this,
    load: load,
    serverMiddleware: List<StartMiddleware>.unmodifiable(middleware),
    handlers: Map<StartMethod, ServerRouteHandler<P, S>>.unmodifiable(
      handlers ?? <StartMethod, ServerRouteHandler<P, S>>{},
    ),
  );
}
