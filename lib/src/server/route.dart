// ignore_for_file: public_member_api_docs

import 'dart:async';

import '../document/document.dart';
import '../query/client.dart';
import '../router/codec.dart';
import '../router/match.dart';
import '../router/pattern.dart';
import '../router/route.dart';
import 'context.dart';
import 'http.dart';
import 'middleware.dart';

/// Typed input for one public HTTP route handler.
final class ServerRouteContext<P, S> {
  const ServerRouteContext({
    required this.request,
    required this.params,
    required this.search,
    required this.location,
  });

  final RequestContext request;
  final P params;
  final S search;
  final Uri location;
}

typedef ServerRouteHandler<P, S> =
    FutureOr<ServerResponse> Function(ServerRouteContext<P, S> context);

/// Server-only behavior attached to a client-safe route definition.
final class ServerRoute<P, S, D> implements TypedRoute<P, S, D> {
  ServerRoute._({
    required this.definition,
    required this.load,
    required this.serverMiddleware,
    required this.handlers,
  });

  /// The shared route contract.
  final AppRoute<P, S, D> definition;

  /// Optional server loader implementation.
  final RouteLoader<P, S, D>? load;

  final List<Middleware> serverMiddleware;

  /// Public HTTP handlers keyed by method.
  final Map<HttpMethod, ServerRouteHandler<P, S>> handlers;

  @override
  List<RouteNode> get children => definition.children;

  @override
  RoutePattern get compiledPattern => definition.compiledPattern;

  @override
  bool get hasPathCodec => definition.hasPathCodec;

  @override
  bool get hasDocument => definition.hasDocument;

  @override
  bool get hasFlutterPage => definition.hasFlutterPage;

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
    RouteBranch branch,
    QueryClient query,
  ) {
    final loader = load;
    if (loader == null) {
      return definition.loadObject(params, search, location, branch, query);
    }
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
  ) => definition.buildDocumentObject(params, search, data, location, branch);

  @override
  List<String> encodePath(Object? params) => definition.encodePath(params);

  @override
  Map<String, List<String>> encodeQuery(Object? search) =>
      definition.encodeQuery(search);

  bool handles(HttpMethod method) =>
      handlers.containsKey(method) ||
      (method == HttpMethod.head && handlers.containsKey(HttpMethod.get));

  Future<ServerResponse>? handle(
    HttpMethod method,
    RequestContext request,
    RouteMatches matches,
  ) {
    final handler =
        handlers[method] ??
        (method == HttpMethod.head ? handlers[HttpMethod.get] : null);
    if (handler == null) return null;
    final match = matches.match(this)!;
    return Future<ServerResponse>.sync(
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
  ServerRoute<P, S, D> withChildren(Iterable<RouteNode> children) =>
      ServerRoute<P, S, D>._(
        definition: definition.withChildren(children),
        load: load,
        serverMiddleware: serverMiddleware,
        handlers: handlers,
      );

  /// Binds generated file-system path information.
  ServerRoute<P, S, D> compiled({
    required String path,
    PathParams<P>? params,
    SearchParams<S>? search,
    required bool terminal,
    bool hasFlutterPage = false,
    Iterable<RouteNode> children = const <RouteNode>[],
  }) => ServerRoute<P, S, D>._(
    definition: definition.compiled(
      path: path,
      params: params,
      search: search,
      terminal: terminal,
      hasFlutterPage: hasFlutterPage,
      children: children,
    ),
    load: load,
    serverMiddleware: serverMiddleware,
    handlers: handlers,
  );
}

/// Attaches server-only behavior to an app route.
extension AppRouteServer<P, S, D> on AppRoute<P, S, D> {
  ServerRoute<P, S, D> server({
    RouteLoader<P, S, D>? load,
    Iterable<Middleware> middleware = const <Middleware>[],
    Map<HttpMethod, ServerRouteHandler<P, S>>? handlers,
  }) => ServerRoute<P, S, D>._(
    definition: this,
    load: load,
    serverMiddleware: List<Middleware>.of(middleware, growable: false),
    handlers: Map<HttpMethod, ServerRouteHandler<P, S>>.of(
      handlers ?? <HttpMethod, ServerRouteHandler<P, S>>{},
    ),
  );
}
