import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../app/context.dart';
import '../app/module.dart';
import '../router/load.dart';
import '../router/match.dart';
import '../router/route.dart';
import '../rpc/function.dart';
import '../rpc/serializer.dart';
import 'context.dart';
import 'http.dart';
import 'middleware.dart';
import 'render.dart';
import 'route.dart';

/// Handles one platform-neutral server request.
typedef ServerHandler = Future<ServerResponse> Function(ServerRequest request);

/// Adapter-neutral runtime for typed routes and server functions.
final class Server {
  /// Creates a server from explicitly selected routes and capabilities.
  Server({
    required Iterable<RouteNode> routes,
    Map<String, ServerFunctionBinding> functions =
        const <String, ServerFunctionBinding>{},
    Iterable<Middleware> middleware = const <Middleware>[],
    Iterable<Module> Function()? modules,
    Iterable<RouteNode> flutterRoutes = const <RouteNode>[],
    Serializer? serializer,
    this.renderer,
    this.functionPath = '/__odroe/functions',
    this.maxFunctionPayload = 1024 * 1024,
    this.exposeErrors = false,
    this.allowRpcWithoutOrigin = false,
  }) : routes = List<RouteNode>.of(routes, growable: false),
       functions = Map<String, ServerFunctionBinding>.of(functions),
       middleware = List<Middleware>.of(middleware, growable: false),
       modules = modules ?? _emptyModules,
       serializer = serializer ?? Serializer(),
       _flutterRoutes = HashSet<Object>.identity()
         ..addAll(flutterRoutes.map((route) => route.identity)),
       _functionPrefix = functionPath.endsWith('/')
           ? functionPath
           : '$functionPath/' {
    _matcher = RouteMatcher(this.routes);
  }

  /// Routes matched by this server.
  final List<RouteNode> routes;

  /// Server function bindings keyed by generated identifier.
  final Map<String, ServerFunctionBinding> functions;

  /// Middleware applied to every request.
  final List<Middleware> middleware;

  /// Creates explicitly selected request-scoped modules.
  final Iterable<Module> Function() modules;

  /// Serializer shared by server functions and renderers.
  final Serializer serializer;

  /// Optional renderer used by GET and HEAD routes without a direct handler.
  final Renderer? renderer;

  /// Prefix used by generated server functions.
  final String functionPath;

  /// Maximum buffered server function payload size.
  final int maxFunctionPayload;

  /// Whether failure responses may expose internal details.
  final bool exposeErrors;

  /// Whether RPC requests without origin metadata are accepted.
  final bool allowRpcWithoutOrigin;

  final Set<Object> _flutterRoutes;
  final String _functionPrefix;
  late final RouteMatcher _matcher;

  /// A handler suitable for platform adapters.
  ServerHandler get handler => handle;

  /// Handles one request and disposes its modules after the body is consumed.
  Future<ServerResponse> handle(ServerRequest request) async {
    final app = await AppContext.create(modules());
    final context = RequestContext(request: request, app: app);
    final rpcId = _rpcId(request.uri.path);
    late final ServerResponse response;
    try {
      response = await runMiddleware(
        context,
        middleware,
        () => rpcId == null
            ? _handleRoute(context)
            : _handleFunction(context, rpcId),
      );
    } on Redirect catch (redirect) {
      response = _controlResponse(
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
      response = _failure(
        request,
        rpc: rpcId != null,
        status: 404,
        title: 'Page not found',
        message: error.message,
        error: error,
      );
    } on HttpError catch (error) {
      response = _failure(
        request,
        rpc: rpcId != null,
        status: error.status,
        title: 'Request failed',
        message: error.message,
        error: error,
        headers: error.headers,
      );
    } on PayloadTooLargeException catch (error) {
      response = _failure(
        request,
        rpc: rpcId != null,
        status: 413,
        title: 'Payload too large',
        message: '$error',
        error: error,
      );
    } on Object catch (error, stackTrace) {
      response = _failure(
        request,
        rpc: rpcId != null,
        status: 500,
        title: 'Internal server error',
        message: exposeErrors ? '$error' : 'Internal server error.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return _withCleanup(response, app, request);
  }

  ServerResponse _failure(
    ServerRequest request, {
    required bool rpc,
    required int status,
    required String title,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Headers? headers,
  }) {
    final accept = request.headers.value('accept')?.toLowerCase() ?? '*/*';
    if (!rpc &&
        (!accept.contains('application/json') ||
            accept.contains('text/html'))) {
      final detail = exposeErrors && stackTrace != null
          ? '<pre>${_text('$error\n$stackTrace')}</pre>'
          : '';
      final response = ServerResponse.html(
        '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="robots" content="noindex,nofollow">'
        '<title>${_text(title)}</title></head><body><main>'
        '<h1>${_text(title)}</h1><p>${_text(message)}</p>$detail'
        '</main></body></html>',
        status: status,
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
      if (route is ServerRoute) routeMiddleware.addAll(route.middleware);
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
    final render = renderer;
    if (render == null) {
      throw const NotFound('The matched route has no response renderer.');
    }
    return runMiddleware(context, routeMiddleware, () async {
      final loads = await _load(context, matches);
      final firstError = loads.values
          .where((result) => result.isLoaded && !result.hasData)
          .firstOrNull;
      if (firstError != null) {
        Error.throwWithStackTrace(firstError.error!, firstError.stackTrace!);
      }
      return render(
        RenderContext(
          request: context,
          matches: matches,
          loads: loads,
          serializer: serializer,
          flutter: _flutterRoutes.contains(last.identity),
        ),
      );
    });
  }

  Future<Map<Object, RouteLoadResult>> _load(
    RequestContext context,
    RouteMatches matches,
  ) async {
    final loads = HashMap<Object, RouteLoadResult>.identity();
    await Future.wait<void>(
      matches.routes.map((route) async {
        if (route is! ServerRoute) {
          loads[route.identity] = const RouteLoadResult.client();
          return;
        }
        try {
          final data = await route.runLoader(context, matches);
          loads[route.identity] = RouteLoadResult.data(data);
        } on Object catch (error, stackTrace) {
          loads[route.identity] = RouteLoadResult.error(error, stackTrace);
        }
      }),
    );
    return UnmodifiableMapView<Object, RouteLoadResult>(loads);
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
    AppContext app,
    ServerRequest request,
  ) {
    if (request.method == HttpMethod.head) {
      unawaited(app.dispose());
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
        await app.dispose();
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

Iterable<Module> _emptyModules() => const <Module>[];

String _text(String value) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(value);
