import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:js_interop';

import 'package:odroe/router.dart';
import 'package:odroe/server_fetch.dart';

typedef _StrictSearch = ({int page});

final _strictSearchRoute =
    AppRoute<NoParams, _StrictSearch, NoData>(
      path: '/typed-search',
      search: SearchParams<_StrictSearch>.codec(
        keys: const <String>{'page'},
        defaults: (page: 1),
        invalid: InvalidSearchBehavior.error,
        decode: (input) => (page: input.integer('page') ?? 1),
        encode: (value, output) => output.integer('page', value.page),
      ),
    ).server(
      handlers: <HttpMethod, ServerRouteHandler<NoParams, _StrictSearch>>{
        HttpMethod.get: (context) =>
            ServerResponse.json(<String, Object?>{'page': context.search.page}),
      },
    );

void main() {
  final server = Server(
    routes: <RouteNode>[_strictSearchRoute],
    onError: _reportError,
    middleware: <Middleware>[
      (context, next) => context.request.uri.path == '/typed-search'
          ? next()
          : _handle(context.request, context.invocation),
    ],
  );
  exportFetchHandler(server.invocationHandler, onError: server.onError);
}

Future<void> _reportError(
  ServerRequest request,
  Object error,
  StackTrace stackTrace,
) async {
  _testState
    ..reportCount = _testState.reportCount + 1
    ..reportMethod = request.method.wire
    ..reportPath = request.uri.path
    ..reportError = '$error'
    ..reportStack = '$stackTrace'
    ..reportCompleted = false;
  await Future<void>.delayed(const Duration(milliseconds: 5));
  _testState.reportCompleted = true;
}

Future<ServerResponse> _handle(
  ServerRequest request,
  ServerInvocation invocation,
) async {
  final env = _Environment(invocation.requireBindings<FetchBindings>().raw);
  switch (request.uri.path) {
    case '/echo':
      final body = await request.readBytes();
      final headers = Headers()
        ..set('x-method', request.method.wire)
        ..set('x-query', request.uri.query)
        ..set('x-request-header', request.headers.value('x-request') ?? '')
        ..set('x-binding', env.marker)
        ..append('x-multi', 'one')
        ..append('x-multi', 'two')
        ..append('set-cookie', 'a=1')
        ..append('set-cookie', 'b=2');
      return ServerResponse(
        status: 201,
        reason: 'Created by Odroe',
        headers: headers,
        body: Stream<List<int>>.value(body),
      );
    case '/request-cancel':
      return ServerResponse.bytes(await request.body.first);
    case '/request-stream':
      return ServerResponse(body: request.body);
    case '/abort':
      await request.cancelled!;
      return ServerResponse.text('cancelled', status: 499);
    case '/stream':
      Stream<List<int>> body() async* {
        try {
          for (var index = 0; index < 5; index++) {
            env.produced = index + 1;
            yield utf8.encode('$index');
          }
        } finally {
          env.responseCancelled = true;
        }
      }

      return ServerResponse(body: body());
    case '/error-cancel':
      return ServerResponse(body: _errorBody(env));
    case '/head':
      return ServerResponse(body: _discardedBody(env));
    case '/wait':
      invocation.waitUntil(
        Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      return ServerResponse.text('scheduled');
    case '/invalid-response':
      return ServerResponse(status: 700, body: _discardedBody(env));
    case '/invalid-response-header':
      return ServerResponse(
        headers: Headers()..set('bad\nname', 'value'),
        body: _discardedBody(env),
      );
    case '/invalid-response-stream':
      return ServerResponse(body: Stream<List<int>>.value(_FailingBytes()));
    default:
      if (request.uri.path.startsWith('/status/')) {
        final status = int.parse(request.uri.path.split('/').last);
        return ServerResponse(status: status, body: _discardedBody(env));
      }
      return ServerResponse.text('not found', status: 404);
  }
}

Stream<List<int>> _errorBody(_Environment env) {
  late final StreamController<List<int>> controller;
  controller = StreamController<List<int>>(
    onListen: () {
      controller
        ..add(utf8.encode('first'))
        ..addError(StateError('response failed'));
    },
    onCancel: () async {
      env.responseCancelStarted = true;
      while (!env.releaseResponseCancel) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      env.responseCancelled = true;
    },
  );
  return controller.stream;
}

Stream<List<int>> _discardedBody(_Environment env) async* {
  try {
    yield <int>[1, 2, 3];
  } finally {
    env.responseCancelled = true;
  }
}

final class _FailingBytes extends ListBase<int> {
  @override
  int get length => 1;

  @override
  set length(int value) => throw UnsupportedError('fixed length');

  @override
  int operator [](int index) => throw StateError('byte conversion failed');

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('read only');
}

extension type _Environment(JSObject _) implements JSObject {
  external String get marker;

  external int get produced;
  external set produced(int value);

  external bool get responseCancelled;
  external set responseCancelled(bool value);

  external bool get responseCancelStarted;
  external set responseCancelStarted(bool value);

  external bool get releaseResponseCancel;
}

@JS('globalThis')
external _TestState get _testState;

extension type _TestState(JSObject _) implements JSObject {
  external int get reportCount;
  external set reportCount(int value);

  external String get reportMethod;
  external set reportMethod(String value);

  external String get reportPath;
  external set reportPath(String value);

  external String get reportError;
  external set reportError(String value);

  external String get reportStack;
  external set reportStack(String value);

  external bool get reportCompleted;
  external set reportCompleted(bool value);
}
