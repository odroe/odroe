// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';

import '../query/client.dart';
import '../query/hydration.dart';
import '../query/managers.dart';
import '../router/codec.dart';
import '../router/match.dart';
import '../router/route.dart';
import 'context.dart';
import 'middleware.dart';
import 'request.dart';
import 'serialization.dart';
import 'server_function.dart';
import 'server_route.dart';

typedef StartHandler = Future<StartResponse> Function(StartRequest request);
typedef StartRenderer =
    FutureOr<StartResponse> Function(StartRenderContext context);

/// Input for HTML, JSON, or custom first-screen renderers.
final class StartRenderContext {
  const StartRenderContext({
    required this.request,
    required this.matches,
    required this.loads,
    required this.query,
    required this.dehydrated,
    required this.serializer,
  });

  final StartRequestContext request;
  final RouteMatches matches;
  final Map<Object, RouteLoadResult> loads;
  final QueryClient query;
  final DehydratedState dehydrated;
  final StartSerializer serializer;
}

/// Runtime options shared by generated and manually assembled Start apps.
final class StartOptions {
  const StartOptions({
    this.functionPath = '/__odroe/functions',
    this.maxFunctionPayload = 1024 * 1024,
    this.exposeErrors = false,
    this.allowRpcWithoutOrigin = false,
  });

  final String functionPath;
  final int maxFunctionPayload;
  final bool exposeErrors;
  final bool allowRpcWithoutOrigin;
}

/// Adapter-neutral Start application composed from the generated route tree.
final class StartApplication {
  StartApplication({
    required Iterable<AnyAppRoute> routes,
    Map<String, AnyServerFunction> functions =
        const <String, AnyServerFunction>{},
    Iterable<StartMiddleware> middleware = const <StartMiddleware>[],
    StartSerializer? serializer,
    StartRenderer? renderer,
    this.options = const StartOptions(),
  }) : routes = List<AnyAppRoute>.unmodifiable(routes),
       functions = Map<String, AnyServerFunction>.unmodifiable(
         functions.map(
           (id, function) =>
               MapEntry(id, function.id == id ? function : function.bind(id)),
         ),
       ),
       middleware = List<StartMiddleware>.unmodifiable(middleware),
       serializer = serializer ?? StartSerializer(),
       renderer = renderer ?? const StartHandoffRenderer().call {
    _matcher = RouteMatcher(this.routes);
  }

  final List<AnyAppRoute> routes;
  final Map<String, AnyServerFunction> functions;
  final List<StartMiddleware> middleware;
  final StartSerializer serializer;
  final StartRenderer renderer;
  final StartOptions options;
  late final RouteMatcher _matcher;

  StartHandler get handler => handle;

  Future<StartResponse> handle(StartRequest request) async {
    final rpc = _rpcId(request.uri.path);
    final type = rpc == null
        ? StartHandlerType.router
        : StartHandlerType.serverFunction;
    final query = QueryClient(
      options: const QueryClientOptions(
        environment: QueryEnvironment(isServer: true),
      ),
    );
    final context = StartRequestContext(
      request: request,
      query: query,
      type: type,
    );
    if (request.cancelled case final cancelled?) {
      unawaited(
        cancelled.then<void>(
          (_) => query.cancelQueries(const QueryFilter(), true, false),
        ),
      );
    }
    final csrf = StartCsrfMiddleware(
      allowRequestsWithoutOrigin: options.allowRpcWithoutOrigin,
    );
    try {
      final response = await runStartMiddleware(
        context,
        <StartMiddleware>[csrf.call, ...middleware],
        () =>
            rpc == null ? _handleRoute(context) : _handleFunction(context, rpc),
      );
      return _withCleanup(response, query, request);
    } on StartRedirect catch (redirect) {
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
    } on StartNotFound catch (notFound) {
      query.clear();
      return StartResponse.json(<String, Object?>{
        'type': 'notFound',
        'message': notFound.message,
      }, status: 404);
    } on StartHttpException catch (error) {
      query.clear();
      return StartResponse.json(
        <String, Object?>{'type': 'error', 'message': error.message},
        status: error.status,
        headers: error.headers,
      );
    } on StartPayloadTooLargeException catch (error) {
      query.clear();
      return StartResponse.json(<String, Object?>{
        'type': 'error',
        'message': error.toString(),
      }, status: 413);
    } on Object catch (error, stackTrace) {
      query.clear();
      return StartResponse.json(<String, Object?>{
        'type': 'error',
        'message': options.exposeErrors ? '$error' : 'Internal server error.',
        if (options.exposeErrors) 'stack': '$stackTrace',
        'errorType': error.runtimeType.toString(),
      }, status: 500);
    }
  }

  String? _rpcId(String path) {
    final prefix = options.functionPath.endsWith('/')
        ? options.functionPath
        : '${options.functionPath}/';
    if (!path.startsWith(prefix)) return null;
    final value = path.substring(prefix.length).split('/').first;
    return value.isEmpty ? null : Uri.decodeComponent(value);
  }

  Future<StartResponse> _handleFunction(
    StartRequestContext context,
    String id,
  ) async {
    final function = functions[id];
    if (function == null) {
      throw const StartNotFound('Server function not found.');
    }
    if (context.request.method != function.method) {
      return StartResponse.text(
        'Expected ${function.method.wire}.',
        status: 405,
        headers: StartHeaders.single(<String, String>{
          'allow': function.method.wire,
        }),
      );
    }
    final payload = await _readFunctionPayload(context.request);
    final decoded = serializer.decode(payload);
    final data = decoded is Map ? decoded['data'] : null;
    final result = await runStartMiddleware(
      context,
      function.middleware,
      () async {
        final value = await function.executeObject(data, context, id);
        if (value is StartResponse) return value;
        if (value is Stream) return _streamFunction(value);
        return StartResponse.json(<String, Object?>{
          'version': 1,
          'type': 'data',
          'data': serializer.encode(value),
        });
      },
    );
    return result;
  }

  Future<Object?> _readFunctionPayload(StartRequest request) async {
    if (request.method == StartMethod.get) {
      final payload = request.uri.queryParameters['payload'];
      if (payload == null || payload.isEmpty) return <String, Object?>{};
      if (utf8.encode(payload).length > options.maxFunctionPayload) {
        throw StartPayloadTooLargeException(options.maxFunctionPayload);
      }
      return jsonDecode(payload);
    }
    return request.readJson(maxBytes: options.maxFunctionPayload);
  }

  StartResponse _streamFunction(Stream<dynamic> stream) {
    Stream<List<int>> body() async* {
      try {
        await for (final value in stream) {
          yield utf8.encode(
            '${jsonEncode(<String, Object?>{'version': 1, 'type': 'data', 'data': serializer.encode(value)})}\n',
          );
        }
      } on Object catch (error) {
        yield utf8.encode(
          '${jsonEncode(<String, Object?>{'version': 1, 'type': 'error', 'message': options.exposeErrors ? '$error' : 'Server stream failed.'})}\n',
        );
      }
    }

    return StartResponse(
      headers: StartHeaders.single(<String, String>{
        'content-type': 'application/x-ndjson; charset=utf-8',
      }),
      body: body(),
    );
  }

  Future<StartResponse> _handleRoute(StartRequestContext context) async {
    final matches = _matcher.match(context.request.uri);
    if (matches == null) throw const StartNotFound();
    final serverRoutes = matches.routes.whereType<AnyServerRoute>().toList();
    final middleware = serverRoutes
        .expand((route) => route.serverMiddleware)
        .toList(growable: false);
    final matchedLeaf = matches.routes.last;
    final leaf = matchedLeaf is AnyServerRoute ? matchedLeaf : null;
    final routeHandler = leaf?.handle(context.request.method, context, matches);
    if (routeHandler != null) {
      context.type = StartHandlerType.serverRoute;
      final response = await runStartMiddleware(
        context,
        middleware,
        () => routeHandler,
      );
      if (context.request.method == StartMethod.head) {
        return StartResponse(
          status: response.status,
          reason: response.reason,
          headers: response.headers,
        );
      }
      return response;
    }
    if (context.request.method != StartMethod.get &&
        context.request.method != StartMethod.head) {
      return StartResponse.text('Method not allowed.', status: 405);
    }
    return runStartMiddleware(context, middleware, () async {
      final loads = await matches.loadAll(query: context.query);
      final firstError = loads.values
          .where((result) => !result.hasData)
          .firstOrNull;
      if (firstError != null) {
        Error.throwWithStackTrace(firstError.error!, firstError.stackTrace!);
      }
      final dehydrated = dehydrate(
        context.query,
        serializeData: serializer.encode,
        includePending: true,
      );
      return renderer(
        StartRenderContext(
          request: context,
          matches: matches,
          loads: loads,
          query: context.query,
          dehydrated: dehydrated,
          serializer: serializer,
        ),
      );
    });
  }

  StartResponse _controlResponse(
    StartRequest request,
    Map<String, Object?> frame, {
    required int status,
    required Uri location,
  }) => request.headers.value('x-odroe-server-function') == 'true'
      ? StartResponse.json(frame, status: status)
      : StartResponse.redirect(location, status: status);

  StartResponse _withCleanup(
    StartResponse response,
    QueryClient query,
    StartRequest request,
  ) {
    if (request.method == StartMethod.head) {
      query.clear();
      return response;
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

    return StartResponse(
      status: response.status,
      reason: response.reason,
      headers: response.headers,
      body: body(),
    );
  }
}

/// Default first-screen handoff for Flutter web and JSON clients.
final class StartHandoffRenderer {
  const StartHandoffRenderer({this.flutterBootstrap = '/flutter_bootstrap.js'});

  final String flutterBootstrap;

  StartResponse call(StartRenderContext context) {
    final payload = <String, Object?>{
      'version': 1,
      'location': context.matches.location.toString(),
      'loads': context.matches.routes
          .map((route) => context.loads[route.identity]!)
          .map((result) => _encodeLoad(result, context.serializer))
          .toList(growable: false),
      'query': context.dehydrated.toJson(),
    };
    final accept = context.request.request.headers.value('accept') ?? '*/*';
    final pending = _pendingFrames(context);
    final hasPending = context.dehydrated.queries.any(
      (query) => query.pending != null,
    );
    if (accept.contains('application/json') && !accept.contains('text/html')) {
      if (!hasPending) return StartResponse.json(payload);
      return StartResponse(
        headers: StartHeaders.single(<String, String>{
          'content-type': 'application/x-ndjson; charset=utf-8',
        }),
        body: _jsonHandoff(payload, pending),
      );
    }
    final encoded = _escapeScript(jsonEncode(payload));
    return StartResponse(
      headers: StartHeaders.single(<String, String>{
        'content-type': 'text/html; charset=utf-8',
      }),
      body: _htmlHandoff(encoded, pending),
    );
  }

  Map<String, Object?> _encodeLoad(
    RouteLoadResult result,
    StartSerializer serializer,
  ) => result.data is NoData
      ? const <String, Object?>{'type': 'noData'}
      : <String, Object?>{
          'type': 'data',
          'data': serializer.encode(result.data),
        };

  Stream<List<int>> _jsonHandoff(
    Map<String, Object?> initial,
    Stream<Map<String, Object?>> pending,
  ) async* {
    yield utf8.encode(
      '${jsonEncode(<String, Object?>{'version': 1, 'type': 'initial', 'data': initial})}\n',
    );
    await for (final frame in pending) {
      yield utf8.encode('${jsonEncode(frame)}\n');
    }
  }

  Stream<List<int>> _htmlHandoff(
    String initial,
    Stream<Map<String, Object?>> pending,
  ) async* {
    yield utf8.encode(
      '<!doctype html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '</head><body><script id="__odroe_state__" type="application/json">'
      '$initial</script><script src="${htmlEscape.convert(flutterBootstrap)}" '
      'async></script>',
    );
    await for (final frame in pending) {
      final encoded = _escapeScript(jsonEncode(frame));
      yield utf8.encode(
        '<script type="application/json" data-odroe-frame>$encoded</script>',
      );
    }
    yield utf8.encode('</body></html>');
  }

  Stream<Map<String, Object?>> _pendingFrames(StartRenderContext context) {
    final pending = context.dehydrated.queries
        .where((query) => query.pending != null)
        .toList(growable: false);
    if (pending.isEmpty) return const Stream<Map<String, Object?>>.empty();
    late final StreamController<Map<String, Object?>> controller;
    var remaining = pending.length;
    void completeOne() {
      remaining--;
      if (remaining == 0) controller.close();
    }

    controller = StreamController<Map<String, Object?>>(sync: true);
    for (final item in pending) {
      item.pending!.then<void>(
        (data) {
          final now = context.query.scheduler.now();
          final state = <String, Object?>{
            ...item.state,
            'status': 'success',
            'hasData': true,
            'data': data,
            'dataUpdatedAt': now.millisecondsSinceEpoch,
            'dataUpdateCount': (item.state['dataUpdateCount']! as int) + 1,
            'fetchFailureCount': 0,
            'isInvalidated': false,
          };
          controller.add(<String, Object?>{
            'version': 1,
            'type': 'query',
            'query': DehydratedQuery(
              key: item.key,
              state: state,
              dehydratedAt: now,
              meta: item.meta,
            ).toJson(),
          });
          completeOne();
        },
        onError: (Object _, StackTrace _) {
          final now = context.query.scheduler.now();
          final state = <String, Object?>{
            ...item.state,
            'status': 'error',
            'error': 'Query failed.',
            'errorUpdatedAt': now.millisecondsSinceEpoch,
            'errorUpdateCount': (item.state['errorUpdateCount']! as int) + 1,
            'fetchFailureCount': (item.state['fetchFailureCount']! as int) + 1,
          };
          controller.add(<String, Object?>{
            'version': 1,
            'type': 'queryError',
            'key': item.key.toJson(),
            'message': 'Query failed.',
            'query': DehydratedQuery(
              key: item.key,
              state: state,
              dehydratedAt: now,
              meta: item.meta,
            ).toJson(),
          });
          completeOne();
        },
      );
    }
    return controller.stream;
  }
}

String _escapeScript(String value) => value.replaceAllMapped(
  RegExp(r'</script', caseSensitive: false),
  (_) => r'<\/script',
);
