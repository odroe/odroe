import 'dart:async';

import '../app/context.dart';
import '../app/key.dart';
import '../router/codec.dart';
import '../router/match.dart';
import '../router/path.dart';
import '../router/route.dart';
import 'context.dart';
import 'http.dart';
import 'middleware.dart';

/// Typed input for one server route loader.
final class ServerLoadContext<P, S> {
  /// Creates server loader input.
  const ServerLoadContext({
    required this.context,
    required this.params,
    required this.search,
    required this.location,
    required this.branch,
  });

  /// Request-scoped application and HTTP state.
  final RequestContext context;

  /// Path parameters owned by the route.
  final P params;

  /// Search state owned by the route.
  final S search;

  /// Complete matched location.
  final Uri location;

  /// Complete matched route branch.
  final RouteBranch branch;

  /// Incoming HTTP request.
  ServerRequest get request => context.request;

  /// Explicitly installed request application modules.
  AppContext get app => context.app;

  /// Reads an application service.
  T read<T extends Object>(ContextKey<T> key) => context.read(key);

  /// Reads an optional application service.
  T? maybe<T extends Object>(ContextKey<T> key) => context.maybe(key);

  /// Returns typed values for an active route.
  RouteValues<ParentP, ParentS>? match<ParentP, ParentS, ParentD>(
    TypedRoute<ParentP, ParentS, ParentD> route,
  ) => branch.match(route);
}

/// Loads data for a server route.
typedef ServerLoader<P, S, D> =
    FutureOr<D> Function(ServerLoadContext<P, S> context);

/// Typed input for one public HTTP route handler.
final class ServerRouteContext<P, S> {
  /// Creates route handler input.
  const ServerRouteContext({
    required this.context,
    required this.params,
    required this.search,
    required this.location,
  });

  /// Request-scoped application and HTTP state.
  final RequestContext context;

  /// Path parameters owned by the route.
  final P params;

  /// Search state owned by the route.
  final S search;

  /// Complete matched location.
  final Uri location;

  /// Incoming HTTP request.
  ServerRequest get request => context.request;

  /// Explicitly installed request application modules.
  AppContext get app => context.app;

  /// Reads an application service.
  T read<T extends Object>(ContextKey<T> key) => context.read(key);

  /// Reads an optional application service.
  T? maybe<T extends Object>(ContextKey<T> key) => context.maybe(key);
}

/// Handles one HTTP method on a matched route.
typedef ServerRouteHandler<P, S> =
    FutureOr<ServerResponse> Function(ServerRouteContext<P, S> context);

/// Server behavior attached to a neutral route definition.
final class ServerRoute<P, S, D> implements TypedRoute<P, S, D> {
  ServerRoute._({
    required this.definition,
    required this.load,
    required this.middleware,
    required this.handlers,
  });

  /// The shared route definition.
  final AppRoute<P, S, D> definition;

  /// Optional server loader implementation.
  final ServerLoader<P, S, D>? load;

  /// Middleware applied when this route is active.
  final List<Middleware> middleware;

  /// Public HTTP handlers keyed by method.
  final Map<HttpMethod, ServerRouteHandler<P, S>> handlers;

  @override
  List<RouteNode> get children => definition.children;

  @override
  PathTemplate get template => definition.template;

  @override
  bool get hasPathCodec => definition.hasPathCodec;

  @override
  RouteMetadata get metadata => definition.metadata;

  @override
  Object get identity => definition.identity;

  @override
  String? get path => definition.path;

  @override
  bool get terminal => definition.terminal;

  @override
  T? capability<T extends Object>(RouteCapability<T> key) =>
      definition.capability(key);

  @override
  Object? decodePath(Map<String, List<String>> values) =>
      definition.decodePath(values);

  @override
  DecodedSearch<Object?> decodeQuery(Map<String, List<String>> values) =>
      definition.decodeQuery(values);

  @override
  List<String> encodePath(Object? params) => definition.encodePath(params);

  @override
  Map<String, List<String>> encodeQuery(Object? search) =>
      definition.encodeQuery(search);

  /// Runs this route's loader for the active branch.
  FutureOr<Object?> runLoader(RequestContext context, RouteMatches matches) {
    final loader = load;
    if (loader == null) return const NoData();
    final match = matches.match(this);
    if (match == null) {
      throw StateError('Server route is not part of the active route branch.');
    }
    return loader(
      ServerLoadContext<P, S>(
        context: context,
        params: match.params,
        search: match.search,
        location: matches.location,
        branch: matches.branch,
      ),
    );
  }

  /// Whether this route handles [method].
  bool handles(HttpMethod method) =>
      handlers.containsKey(method) ||
      (method == HttpMethod.head && handlers.containsKey(HttpMethod.get));

  /// Runs the handler for [method], or returns `null` when none exists.
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
          context: request,
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
        middleware: middleware,
        handlers: handlers,
      );

  /// Binds generated file-system path information.
  ServerRoute<P, S, D> compiled({
    required String path,
    PathParams<P>? params,
    SearchParams<S>? search,
    required bool terminal,
    Iterable<RouteNode> children = const <RouteNode>[],
  }) => ServerRoute<P, S, D>._(
    definition: definition.compiled(
      path: path,
      params: params,
      search: search,
      terminal: terminal,
      children: children,
    ),
    load: load,
    middleware: middleware,
    handlers: handlers,
  );
}

/// Attaches server behavior to a neutral route definition.
extension AppRouteServer<P, S, D> on AppRoute<P, S, D> {
  /// Creates a server route.
  ServerRoute<P, S, D> server({
    ServerLoader<P, S, D>? load,
    Iterable<Middleware> middleware = const <Middleware>[],
    Map<HttpMethod, ServerRouteHandler<P, S>>? handlers,
  }) => ServerRoute<P, S, D>._(
    definition: this,
    load: load,
    middleware: List<Middleware>.of(middleware, growable: false),
    handlers: Map<HttpMethod, ServerRouteHandler<P, S>>.of(
      handlers ?? <HttpMethod, ServerRouteHandler<P, S>>{},
    ),
  );
}
