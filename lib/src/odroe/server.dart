// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';

import '../query/client.dart';
import '../query/managers.dart';
import '../rpc/function.dart';
import '../rpc/serializer.dart';
import '../router/match.dart';
import '../router/route.dart';
import '../server/context.dart';
import '../server/http.dart';
import '../server/middleware.dart';
import '../server/route.dart';
import 'failure.dart';
import 'render.dart';

typedef ServerHandler = Future<ServerResponse> Function(ServerRequest request);

/// Adapter-neutral runtime for one generated Odroe application.
final class OdroeServer {
  OdroeServer({
    required Iterable<RouteNode> routes,
    Map<String, ServerFunctionBinding> functions =
        const <String, ServerFunctionBinding>{},
    Iterable<Middleware> middleware = const <Middleware>[],
    Serializer? serializer,
    Renderer? renderer,
    this.functionPath = '/__odroe/functions',
    this.maxFunctionPayload = 1024 * 1024,
    this.exposeErrors = false,
    this.allowRpcWithoutOrigin = false,
  }) : routes = List<RouteNode>.of(routes, growable: false),
       functions = Map<String, ServerFunctionBinding>.of(functions),
       middleware = List<Middleware>.of(middleware, growable: false),
       serializer = serializer ?? Serializer(),
       renderer =
           renderer ??
           const DocumentRenderer(
             flutterBootstrap: '/flutter_bootstrap.js',
             baseHref: '/',
           ).call,
       _functionPrefix = functionPath.endsWith('/')
           ? functionPath
           : '$functionPath/' {
    _matcher = RouteMatcher(this.routes);
  }

  final List<RouteNode> routes;
  final Map<String, ServerFunctionBinding> functions;
  final List<Middleware> middleware;
  final Serializer serializer;
  final Renderer renderer;
  final String functionPath;
  final int maxFunctionPayload;
  final bool exposeErrors;
  final bool allowRpcWithoutOrigin;
  final String _functionPrefix;
  late final RouteMatcher _matcher;

  ServerHandler get handler => handle;

  Future<ServerResponse> handle(ServerRequest request) async {
    final rpcId = _rpcId(request.uri.path);
    final query = QueryClient(
      options: const QueryClientOptions(
        environment: QueryEnvironment(isServer: true),
      ),
    );
    final context = RequestContext(request: request, query: query);
    if (request.cancelled case final cancelled?) {
      unawaited(
        cancelled.then<void>(
          (_) => query.cancelQueries(const QueryFilter(), true, false),
        ),
      );
    }

    try {
      final response = await runMiddleware(
        context,
        middleware,
        () => rpcId == null
            ? _handleRoute(context)
            : _handleFunction(context, rpcId),
      );
      return _withCleanup(response, query, request);
    } on Redirect catch (redirect) {
      query.clear();
      return _controlResponse(
        request,
        <String, Object?>{
          'type': 'redirect',
          'location': redirect.location.toString(),
          'status': redirect.status,
        },
        status: redirect.status,
        location: redirect.location,
      );
    } on NotFound catch (error) {
      query.clear();
      return _failure(
        context,
        rpc: rpcId != null,
        status: 404,
        title: 'Page not found',
        message: error.message,
        error: error,
      );
    } on HttpError catch (error) {
      query.clear();
      return _failure(
        context,
        rpc: rpcId != null,
        status: error.status,
        title: 'Request failed',
        message: error.message,
        error: error,
        headers: error.headers,
      );
    } on PayloadTooLargeException catch (error) {
      query.clear();
      return _failure(
        context,
        rpc: rpcId != null,
        status: 413,
        title: 'Payload too large',
        message: '$error',
        error: error,
      );
    } on Object catch (error, stackTrace) {
      query.clear();
      return _failure(
        context,
        rpc: rpcId != null,
        status: 500,
        title: 'Internal server error',
        message: exposeErrors ? '$error' : 'Internal server error.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<ServerResponse> _failure(
    RequestContext context, {
    required bool rpc,
    required int status,
    required String title,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Headers? headers,
  }) async {
    final accept =
        context.request.headers.value('accept')?.toLowerCase() ?? '*/*';
    if (!rpc &&
        (!accept.contains('application/json') ||
            accept.contains('text/html'))) {
      final response = renderFailureDocument(
        status: status,
        title: title,
        message: message,
        details: exposeErrors && stackTrace != null
            ? '$error\n$stackTrace'
            : null,
      );
      if (headers == null) return response;
      return ServerResponse(
        status: response.status,
        reason: response.reason,
        headers: response.headers.copy()..addAll(headers),
        body: response.body,
      );
    }
    return ServerResponse.json(
      <String, Object?>{
        'type': status == 404 ? 'notFound' : 'error',
        'message': message,
        if (exposeErrors && stackTrace != null) 'stack': '$stackTrace',
        if (error != null) 'errorType': error.runtimeType.toString(),
      },
      status: status,
      headers: headers,
    );
  }

  String? _rpcId(String path) {
    if (!path.startsWith(_functionPrefix)) return null;
    final value = path.substring(_functionPrefix.length).split('/').first;
    return value.isEmpty ? null : Uri.decodeComponent(value);
  }

  Future<ServerResponse> _handleFunction(
    RequestContext context,
    String id,
  ) async {
    final rejection = rejectCrossOriginRpc(
      context.request,
      allowWithoutOrigin: allowRpcWithoutOrigin,
    );
    if (rejection != null) return rejection;

    final binding = functions[id];
    if (binding == null) throw const NotFound('Server function not found.');
    if (context.request.method != binding.method) {
      return ServerResponse.text(
        'Expected ${binding.method.wire}.',
        status: 405,
        headers: Headers.single(<String, String>{'allow': binding.method.wire}),
      );
    }
    final payload = await _readFunctionPayload(context.request);
    final decoded = serializer.decode(payload);
    final data = decoded is Map ? decoded['data'] : null;
    return runMiddleware(context, binding.middleware, () async {
      final value = await binding.execute(data, context, id);
      if (value is ServerResponse) return value;
      if (value is Stream) return _streamFunction(value);
      return ServerResponse.json(<String, Object?>{
        'version': 1,
        'type': 'data',
        'data': serializer.encode(value),
      });
    });
  }

  Future<Object?> _readFunctionPayload(ServerRequest request) {
    if (request.method != HttpMethod.get) {
      return request.readJson(maxBytes: maxFunctionPayload);
    }
    final payload = request.uri.queryParameters['payload'];
    if (payload == null || payload.isEmpty) {
      return Future<Object?>.value(<String, Object?>{});
    }
    if (utf8.encode(payload).length > maxFunctionPayload) {
      throw PayloadTooLargeException(maxFunctionPayload);
    }
    return Future<Object?>.value(jsonDecode(payload));
  }

  ServerResponse _streamFunction(Stream<dynamic> stream) {
    Stream<List<int>> body() async* {
      try {
        await for (final value in stream) {
          yield utf8.encode(
            '${jsonEncode(<String, Object?>{'version': 1, 'type': 'data', 'data': serializer.encode(value)})}\n',
          );
        }
      } on Object catch (error) {
        yield utf8.encode(
          '${jsonEncode(<String, Object?>{'version': 1, 'type': 'error', 'message': exposeErrors ? '$error' : 'Server stream failed.'})}\n',
        );
      }
    }

    return ServerResponse(
      headers: Headers.single(<String, String>{
        'content-type': 'application/x-ndjson; charset=utf-8',
      }),
      body: body(),
    );
  }

  Future<ServerResponse> _handleRoute(RequestContext context) async {
    final matches = _matcher.match(context.request.uri);
    if (matches == null) throw const NotFound();

    final routeMiddleware = <Middleware>[];
    for (final route in matches.routes) {
      if (route is ServerRoute) {
        routeMiddleware.addAll(route.serverMiddleware);
      }
    }
    final last = matches.routes.last;
    final serverRoute = last is ServerRoute ? last : null;
    final routeResponse = serverRoute?.handle(
      context.request.method,
      context,
      matches,
    );
    if (routeResponse != null) {
      final response = await runMiddleware(
        context,
        routeMiddleware,
        () => routeResponse,
      );
      if (context.request.method == HttpMethod.head) {
        return ServerResponse(
          status: response.status,
          reason: response.reason,
          headers: response.headers,
        );
      }
      return response;
    }
    if (context.request.method != HttpMethod.get &&
        context.request.method != HttpMethod.head) {
      return ServerResponse.text('Method not allowed.', status: 405);
    }
    return runMiddleware(context, routeMiddleware, () async {
      final loads = await matches.loadAll(query: context.query);
      final firstError = loads.values
          .where((result) => !result.hasData)
          .firstOrNull;
      if (firstError != null) {
        Error.throwWithStackTrace(firstError.error!, firstError.stackTrace!);
      }
      return renderer(
        RenderContext(
          request: context,
          matches: matches,
          loads: loads,
          query: context.query,
          serializer: serializer,
        ),
      );
    });
  }

  ServerResponse _controlResponse(
    ServerRequest request,
    Map<String, Object?> frame, {
    required int status,
    required Uri location,
  }) => request.headers.value('x-odroe-server-function') == 'true'
      ? ServerResponse.json(frame, status: status)
      : ServerResponse.redirect(location, status: status);

  ServerResponse _withCleanup(
    ServerResponse response,
    QueryClient query,
    ServerRequest request,
  ) {
    if (request.method == HttpMethod.head) {
      query.clear();
      return ServerResponse(
        status: response.status,
        reason: response.reason,
        headers: response.headers,
      );
    }
    Stream<List<int>> body() async* {
      try {
        await for (final chunk in response.body) {
          yield chunk;
        }
      } finally {
        query.clear();
      }
    }

    return ServerResponse(
      status: response.status,
      reason: response.reason,
      headers: response.headers,
      body: body(),
    );
  }
}
