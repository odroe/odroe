import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../app/context.dart';
import '../app/module.dart';
import '../router/load.dart';
import '../router/match.dart';
import '../router/route.dart';
import '../rpc/function.dart';
import '../rpc/serializer.dart';
import 'accept.dart';
import 'context.dart';
import 'error_reporter.dart';
import 'http.dart';
import 'invocation.dart';
import 'middleware.dart';
import 'render.dart';
import 'route.dart';

/// Handles one platform-neutral server request.
typedef ServerHandler = Future<ServerResponse> Function(ServerRequest request);

/// Creates request modules from adapter-owned invocation state.
typedef InvocationModuleFactory =
    Iterable<Module> Function(ServerInvocation invocation);

/// Releases application-owned resources after server requests drain.
typedef ServerCloseHandler = FutureOr<void> Function();

/// Adapter-neutral runtime for typed routes and server functions.
final class Server {
  /// Default maximum buffered server-function request size: 1 MiB.
  static const int defaultMaxFunctionPayload = 1024 * 1024;

  /// Default maximum typed server-function response frame size: 1 MiB.
  static const int defaultMaxFunctionResponseFrameBytes = 1024 * 1024;

  /// Smallest valid typed response budget.
  ///
  /// This fits the terminal `{"version":1,"type":"error"}` protocol frame.
  static const int minimumFunctionResponseFrameBytes = 28;

  /// Creates a server from explicitly selected routes and capabilities.
  Server({
    required Iterable<RouteNode> routes,
    Map<String, ServerFunctionBinding> functions =
        const <String, ServerFunctionBinding>{},
    Iterable<Middleware> middleware = const <Middleware>[],
    Iterable<Module> Function()? modules,
    this.invocationModules,
    Iterable<RouteNode> flutterRoutes = const <RouteNode>[],
    Serializer? serializer,
    this.renderer,
    ServerErrorHandler? onError,
    ServerCloseHandler? onClose,
    this.functionPath = '/__odroe/functions',
    this.maxFunctionPayload = defaultMaxFunctionPayload,
    this.maxFunctionResponseFrameBytes = defaultMaxFunctionResponseFrameBytes,
    this.exposeErrors = false,
    this.allowRpcWithoutOrigin = false,
  }) : routes = List<RouteNode>.unmodifiable(routes),
       functions = Map<String, ServerFunctionBinding>.unmodifiable(functions),
       middleware = List<Middleware>.unmodifiable(middleware),
       modules = modules ?? _emptyModules,
       serializer = serializer ?? Serializer(),
       onError = onError ?? defaultServerErrorHandler,
       _onClose = onClose,
       _flutterRoutes = HashSet<Object>.identity()
         ..addAll(flutterRoutes.map((route) => route.identity)),
       _functionPrefix = functionPath.endsWith('/')
           ? functionPath
           : '$functionPath/' {
    if (maxFunctionPayload <= 0) {
      throw ArgumentError.value(
        maxFunctionPayload,
        'maxFunctionPayload',
        'Must be greater than zero.',
      );
    }
    if (maxFunctionResponseFrameBytes < minimumFunctionResponseFrameBytes) {
      throw ArgumentError.value(
        maxFunctionResponseFrameBytes,
        'maxFunctionResponseFrameBytes',
        'Must be at least $minimumFunctionResponseFrameBytes bytes.',
      );
    }
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

  /// Creates additional modules from adapter-owned invocation state.
  ///
  /// These modules are installed only by [handleInvocation]. The binding-free
  /// invocation created by [handle] installs the base [modules] only.
  final InvocationModuleFactory? invocationModules;

  /// Serializer shared by server functions and renderers.
  final Serializer serializer;

  /// Optional renderer used by GET and HEAD routes without a direct handler.
  final Renderer? renderer;

  /// Reports unexpected module setup, request execution, and response stream
  /// failures.
  ///
  /// [ServerRequest.body] may already be consumed when this callback runs; use
  /// request metadata for correlation rather than reading the body again.
  ///
  /// During request dispatch, controlled results such as [Redirect],
  /// [NotFound], [HttpError], payload limits, and normal cancellation are not
  /// reported. Typed frame overflows are never reported. Other response stream
  /// failures are unexpected. Reporter failures fall back to the default Zone
  /// logger and never replace the original outcome. A returned future joins the
  /// invocation lifetime without delaying the response.
  final ServerErrorHandler onError;

  /// Releases long-lived resources after every started invocation settles.
  final ServerCloseHandler? _onClose;

  /// Prefix used by generated server functions.
  final String functionPath;

  /// Maximum buffered server function payload size.
  final int maxFunctionPayload;

  /// Maximum UTF-8 bytes in one typed server-function response frame.
  ///
  /// Streaming functions apply this limit independently to every JSON frame;
  /// the NDJSON line feed is not counted. Explicit [ServerResponse] values
  /// bypass this limit.
  final int maxFunctionResponseFrameBytes;

  /// Whether failure responses may expose internal details.
  final bool exposeErrors;

  /// Whether RPC requests without origin metadata are accepted.
  final bool allowRpcWithoutOrigin;

  final Set<Object> _flutterRoutes;
  final Set<Completer<void>> _activeInvocations = <Completer<void>>{};
  final String _functionPrefix;
  late final RouteMatcher _matcher;
  Future<void>? _closeFuture;

  /// A handler suitable for platform adapters.
  ServerHandler get handler => handle;

  /// An invocation-aware handler suitable for edge adapters.
  ServerInvocationHandler get invocationHandler => handleInvocation;

  /// Handles one request with a binding-free invocation.
  ///
  /// Background work registered through [RequestContext.invocation] keeps the
  /// base request modules alive. Adapter-only [invocationModules] are omitted.
  Future<ServerResponse> handle(ServerRequest request) => _handleInvocation(
    request,
    ServerInvocation(),
    includeInvocationModules: false,
  );

  /// Handles one invocation and disposes its modules after all work completes.
  Future<ServerResponse> handleInvocation(
    ServerRequest request,
    ServerInvocation invocation,
  ) => _handleInvocation(request, invocation, includeInvocationModules: true);

  /// Stops accepting invocations, drains started work, and releases resources.
  ///
  /// The returned future is shared by concurrent and repeated calls. It waits
  /// for every response body, background task, and request module cleanup that
  /// started before this call, then invokes the application [ServerCloseHandler]
  /// once. Call this after the hosting adapter stops accepting requests.
  Future<void> close() {
    final current = _closeFuture;
    if (current != null) return current;

    final completion = Completer<void>();
    _closeFuture = completion.future;
    unawaited(
      _closeApplication().then<void>(
        (_) => completion.complete(),
        onError: (Object error, StackTrace stackTrace) {
          completion.completeError(error, stackTrace);
        },
      ),
    );
    return completion.future;
  }

  Future<ServerResponse> _handleInvocation(
    ServerRequest request,
    ServerInvocation invocation, {
    required bool includeInvocationModules,
  }) async {
    final lifetime = _beginInvocation();
    try {
      startServerInvocation(invocation);
    } on Object {
      _completeInvocation(lifetime);
      rethrow;
    }
    late final AppContext app;
    try {
      final createInvocationModules = includeInvocationModules
          ? invocationModules
          : null;

      Iterable<Module> installedModules() sync* {
        yield* modules();
        if (createInvocationModules != null) {
          yield* createInvocationModules(invocation);
        }
      }

      app = await AppContext.create(
        installedModules(),
        onCleanupError: (error, stackTrace) =>
            _reportUnexpected(request, error, stackTrace, invocation),
      );
    } on Object catch (error, stackTrace) {
      _reportUnexpected(request, error, stackTrace, invocation);
      final cleanup = finishServerInvocation(
        invocation,
        responseDone: Future<void>.value(),
        dispose: () {},
      );
      _trackInvocation(lifetime, cleanup);
      Error.throwWithStackTrace(error, stackTrace);
    }
    var cleanupScheduled = false;
    void scheduleCleanup(Future<void> responseDone) {
      cleanupScheduled = true;
      final cleanup = finishServerInvocation(
        invocation,
        responseDone: responseDone,
        dispose: app.dispose,
      );
      _trackInvocation(lifetime, cleanup);
    }

    try {
      final context = RequestContext(
        request: request,
        app: app,
        invocation: invocation,
      );
      final response = await _dispatch(request, context);
      return _withInvocationCleanup(
        response,
        request,
        invocation,
        scheduleCleanup,
      );
    } on Object catch (error, stackTrace) {
      _reportUnexpected(request, error, stackTrace, invocation);
      if (!cleanupScheduled) scheduleCleanup(Future<void>.value());
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Completer<void> _beginInvocation() {
    if (_closeFuture != null) {
      throw StateError('The server is closing or closed.');
    }
    final lifetime = Completer<void>();
    _activeInvocations.add(lifetime);
    return lifetime;
  }

  void _trackInvocation(Completer<void> lifetime, Future<void> cleanup) {
    unawaited(
      cleanup.then<void>(
        (_) => _completeInvocation(lifetime),
        onError: (Object _, StackTrace _) => _completeInvocation(lifetime),
      ),
    );
  }

  void _completeInvocation(Completer<void> lifetime) {
    _activeInvocations.remove(lifetime);
    if (!lifetime.isCompleted) lifetime.complete();
  }

  Future<void> _closeApplication() async {
    final active = <Future<void>>[
      for (final lifetime in _activeInvocations) lifetime.future,
    ];
    if (active.isNotEmpty) await Future.wait<void>(active);
    await _onClose?.call();
  }

  Future<ServerResponse> _dispatch(
    ServerRequest request,
    RequestContext context,
  ) async {
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
          'version': 1,
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
      _reportUnexpected(request, error, stackTrace, context.invocation);
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
    return response;
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
    final accept = AcceptPreferences.parse(request.headers.value('accept'));
    final responseHeaders = rpc ? headers : _varyAccept(headers);
    if (!rpc && !accept.prefersJson) {
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
      return ServerResponse(
        status: response.status,
        reason: response.reason,
        headers: response.headers.copy()..addAll(responseHeaders!),
        body: response.body,
      );
    }
    final frame = <String, Object?>{
      if (rpc) 'version': 1,
      'type': status == 404 ? 'notFound' : 'error',
      'message': message,
      if (exposeErrors && stackTrace != null) 'stack': '$stackTrace',
      if (error != null) 'errorType': error.runtimeType.toString(),
    };
    if (rpc) {
      return _functionErrorResponse(
        frame,
        status: status,
        headers: responseHeaders,
      );
    }
    return ServerResponse.json(frame, status: status, headers: responseHeaders);
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
    late final Object? decoded;
    try {
      decoded = serializer.decode(payload);
    } on FormatException {
      throw const HttpError(400, 'Invalid server function payload.');
    } on TypeError {
      throw const HttpError(400, 'Invalid server function payload.');
    } on RangeError {
      throw const HttpError(400, 'Invalid server function payload.');
    } on ArgumentError {
      throw const HttpError(400, 'Invalid server function payload.');
    }
    final data = decoded is Map ? decoded['data'] : null;
    return runMiddleware(context, binding.middleware, () async {
      final value = await binding.execute(data, context, id);
      if (value is ServerResponse) return value;
      if (value is Stream) {
        return _streamFunction(value, context.request, context.invocation);
      }
      return _functionResponse(<String, Object?>{
        'version': 1,
        'type': 'data',
        'data': serializer.encode(value),
      });
    });
  }

  Future<Object?> _readFunctionPayload(ServerRequest request) async {
    if (request.method != HttpMethod.get) {
      try {
        return await request.readJson(maxBytes: maxFunctionPayload);
      } on FormatException {
        throw const HttpError(400, 'Invalid server function payload.');
      }
    }
    final payload = request.uri.queryParameters['payload'];
    if (payload == null || payload.isEmpty) {
      return <String, Object?>{};
    }
    if (utf8.encode(payload).length > maxFunctionPayload) {
      throw PayloadTooLargeException(maxFunctionPayload);
    }
    try {
      return jsonDecode(payload);
    } on FormatException {
      throw const HttpError(400, 'Invalid server function payload.');
    }
  }

  ServerResponse _streamFunction(
    Stream<dynamic> stream,
    ServerRequest request,
    ServerInvocation invocation,
  ) {
    Stream<List<int>> body() async* {
      try {
        await for (final value in stream) {
          yield _encodeFunctionFrame(<String, Object?>{
            'version': 1,
            'type': 'data',
            'data': serializer.encode(value),
          }, terminateLine: true);
        }
      } on _FunctionResponseFrameTooLarge {
        yield _encodeFunctionErrorFrame(
          _functionResponseTooLargeFrame,
          terminateLine: true,
        );
      } on Object catch (error, stackTrace) {
        _reportUnexpected(request, error, stackTrace, invocation);
        yield _encodeFunctionErrorFrame(<String, Object?>{
          'version': 1,
          'type': 'error',
          'message': exposeErrors ? '$error' : 'Server stream failed.',
        }, terminateLine: true);
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
      return response;
    }
    if (context.request.method != HttpMethod.get &&
        context.request.method != HttpMethod.head) {
      final allowed = <HttpMethod>{
        for (final method in HttpMethod.values)
          if (serverRoute?.handles(method) ?? false) method,
        if (renderer != null) HttpMethod.get,
        if (renderer != null) HttpMethod.head,
      };
      return ServerResponse.text(
        'Method not allowed.',
        status: 405,
        headers: Headers.single(<String, String>{
          'allow': HttpMethod.values
              .where(allowed.contains)
              .map((method) => method.wire)
              .join(', '),
        }),
      );
    }
    final render = renderer;
    if (render == null) {
      throw const NotFound('The matched route has no response renderer.');
    }
    return runMiddleware(context, routeMiddleware, () async {
      final loads = await _load(context, matches);
      final failedLoads = loads.values
          .where((result) => result.isLoaded && !result.hasData)
          .toList(growable: false);
      final firstError = failedLoads.firstOrNull;
      if (firstError != null) {
        for (final failure in failedLoads.skip(1)) {
          final error = failure.error!;
          if (_isControlledDispatchError(error)) continue;
          _reportUnexpected(
            context.request,
            error,
            failure.stackTrace!,
            context.invocation,
          );
        }
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
      ? _functionResponse(frame, status: status)
      : ServerResponse.redirect(location, status: status);

  Uint8List _encodeFunctionFrame(
    Map<String, Object?> frame, {
    bool terminateLine = false,
  }) => _encodeJsonFrame(
    frame,
    maxFunctionResponseFrameBytes,
    terminateLine: terminateLine,
  );

  Uint8List _encodeFunctionErrorFrame(
    Map<String, Object?> frame, {
    bool terminateLine = false,
  }) {
    try {
      return _encodeFunctionFrame(frame, terminateLine: terminateLine);
    } on _FunctionResponseFrameTooLarge {
      return _encodeFunctionFrame(
        _minimalFunctionErrorFrame,
        terminateLine: terminateLine,
      );
    }
  }

  ServerResponse _functionResponse(
    Map<String, Object?> frame, {
    int status = 200,
    Headers? headers,
  }) {
    try {
      return _functionJsonResponse(
        _encodeFunctionFrame(frame),
        status: status,
        headers: headers,
      );
    } on _FunctionResponseFrameTooLarge {
      return _functionErrorResponse(
        _functionResponseTooLargeFrame,
        status: 500,
        headers: headers,
      );
    }
  }

  ServerResponse _functionErrorResponse(
    Map<String, Object?> frame, {
    required int status,
    Headers? headers,
  }) => _functionJsonResponse(
    _encodeFunctionErrorFrame(frame),
    status: status,
    headers: headers,
  );

  ServerResponse _withInvocationCleanup(
    ServerResponse response,
    ServerRequest request,
    ServerInvocation invocation,
    void Function(Future<void> responseDone) scheduleCleanup,
  ) {
    final omitBody =
        request.method == HttpMethod.head ||
        response.status < 200 ||
        response.status == 204 ||
        response.status == 205 ||
        response.status == 304;
    if (omitBody) {
      final responseDone = _cancelResponseBody(response.body).then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _reportUnexpected(request, error, stackTrace, invocation);
        },
      );
      scheduleCleanup(responseDone);
      return ServerResponse(
        status: response.status,
        reason: response.reason,
        headers: response.headers,
      );
    }

    final responseDone = Completer<void>();
    Stream<List<int>> body() async* {
      try {
        await for (final chunk in response.body) {
          yield chunk;
        }
      } on Object catch (error, stackTrace) {
        _reportUnexpected(request, error, stackTrace, invocation);
        Error.throwWithStackTrace(error, stackTrace);
      } finally {
        if (!responseDone.isCompleted) responseDone.complete();
      }
    }

    scheduleCleanup(responseDone.future);
    return ServerResponse(
      status: response.status,
      reason: response.reason,
      headers: response.headers,
      body: body(),
    );
  }

  void _reportUnexpected(
    ServerRequest request,
    Object error,
    StackTrace stackTrace,
    ServerInvocation invocation,
  ) {
    reportServerError(
      onError,
      request,
      error,
      stackTrace,
      keepAlive: invocation.waitUntil,
    );
  }
}

Future<void> _cancelResponseBody(Stream<List<int>> body) async {
  final subscription = body.listen(null);
  await subscription.cancel();
}

Iterable<Module> _emptyModules() => const <Module>[];

bool _isControlledDispatchError(Object error) =>
    error is Redirect ||
    error is NotFound ||
    error is HttpError ||
    error is PayloadTooLargeException ||
    error is _FunctionResponseFrameTooLarge;

Headers _varyAccept(Headers? headers) {
  final result = headers?.copy() ?? Headers();
  final varies = result
      .values('vary')
      .expand((value) => value.split(','))
      .map((value) => value.trim().toLowerCase());
  if (!varies.contains('*') && !varies.contains('accept')) {
    final current = result.value('vary');
    result.set(
      'vary',
      current == null || current.isEmpty ? 'Accept' : '$current, Accept',
    );
  }
  return result;
}

String _text(String value) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(value);

final _functionFrameEncoder = JsonUtf8Encoder(null, null, 8 * 1024);
const _minimalFunctionErrorFrame = <String, Object?>{
  'version': 1,
  'type': 'error',
};
const _functionResponseTooLargeFrame = <String, Object?>{
  'version': 1,
  'type': 'error',
  'message': 'Server function response exceeded its byte limit.',
};

ServerResponse _functionJsonResponse(
  Uint8List bytes, {
  required int status,
  Headers? headers,
}) => ServerResponse.bytes(
  bytes,
  status: status,
  contentType: 'application/json; charset=utf-8',
  headers: headers,
);

Uint8List _encodeJsonFrame(
  Object? value,
  int maxBytes, {
  bool terminateLine = false,
}) {
  final output = _BoundedByteSink(maxBytes);
  _functionFrameEncoder.startChunkedConversion(output).add(value);
  return output.takeBytes(terminateLine: terminateLine);
}

final class _BoundedByteSink extends ByteConversionSink {
  _BoundedByteSink(this.maxBytes);

  final int maxBytes;
  final List<Uint8List> _chunks = <Uint8List>[];
  var _length = 0;
  var _closed = false;

  @override
  void add(List<int> chunk) => addSlice(chunk, 0, chunk.length, false);

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    final added = end - start;
    if (added > maxBytes - _length) {
      throw _FunctionResponseFrameTooLarge(maxBytes);
    }
    final copy = Uint8List(added)..setRange(0, added, chunk, start);
    _chunks.add(copy);
    _length += added;
    if (isLast) close();
  }

  @override
  void close() => _closed = true;

  Uint8List takeBytes({bool terminateLine = false}) {
    if (!_closed) {
      throw StateError('JSON encoder did not close its output.');
    }
    if (_chunks.length == 1 && !terminateLine) return _chunks.single;

    final result = Uint8List(_length + (terminateLine ? 1 : 0));
    var offset = 0;
    for (final chunk in _chunks) {
      final end = offset + chunk.length;
      result.setRange(offset, end, chunk);
      offset = end;
    }
    if (terminateLine) result[offset] = 0x0a;
    return result;
  }
}

final class _FunctionResponseFrameTooLarge implements Exception {
  const _FunctionResponseFrameTooLarge(this.maxBytes);

  final int maxBytes;

  @override
  String toString() =>
      'Server function response frame exceeds $maxBytes bytes.';
}
