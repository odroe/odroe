import 'dart:async';
import 'dart:convert';

import 'package:odroe/odroe.dart';
import 'package:odroe/router.dart';
import 'package:odroe/server.dart';
import 'package:test/test.dart';

typedef _StrictSearch = ({int page});

typedef _FailureRunner =
    Future<ServerResponse> Function(ServerErrorHandler onError, Object failure);

void main() {
  final requestFailures = <({String name, _FailureRunner run})>[
    (name: 'middleware', run: _middlewareFailure),
    (name: 'route handler', run: _routeHandlerFailure),
    (name: 'loader', run: _loaderFailure),
    (name: 'renderer', run: _rendererFailure),
    (name: 'server function', run: _functionFailure),
    (name: 'server function serialization', run: _serializationFailure),
  ];

  for (final scenario in requestFailures) {
    test('reports an unexpected ${scenario.name} failure once', () async {
      final failure = StateError('${scenario.name} failed');
      final reported =
          <({ServerRequest request, Object error, StackTrace stackTrace})>[];

      final response = await scenario.run(
        (request, error, stackTrace) => reported.add((
          request: request,
          error: error,
          stackTrace: stackTrace,
        )),
        failure,
      );
      final body = await response.readText();

      expect(response.status, 500, reason: body);
      expect(body, isNot(contains('${scenario.name} failed')));
      expect(reported, hasLength(1));
      expect(reported.single.error, same(failure));
      expect(reported.single.request.uri.host, 'localhost');
      expect(
        reported.single.stackTrace.toString(),
        contains('error_reporting_test.dart'),
      );
    });
  }

  for (final phase in _ModuleFailurePhase.values) {
    test('reports a module ${phase.name} failure and rethrows it', () async {
      final failure = StateError('module ${phase.name} failed');
      final reported = <({Object error, StackTrace stackTrace})>[];
      final server = Server(
        routes: const [],
        modules: () {
          if (phase == _ModuleFailurePhase.factory) throw failure;
          return <Module>[_FailingModule(phase, failure)];
        },
        onError: (_, error, stackTrace) =>
            reported.add((error: error, stackTrace: stackTrace)),
      );

      await expectLater(server.handle(_request('/')), throwsA(same(failure)));
      expect(reported, hasLength(1));
      expect(reported.single.error, same(failure));
      expect(
        reported.single.stackTrace.toString(),
        contains('error_reporting_test.dart'),
      );
    });
  }

  test('reports module initialization and rollback cleanup failures', () async {
    final initializationFailure = StateError('module initialize failed');
    final firstCleanupFailure = StateError('first module rollback failed');
    final secondCleanupFailure = StateError('second module rollback failed');
    final reported = <Object>[];
    final server = Server(
      routes: const [],
      modules: () => <Module>[
        _CleanupFailureModule(firstCleanupFailure),
        _FailingModule(
          _ModuleFailurePhase.initialize,
          initializationFailure,
          disposeFailure: secondCleanupFailure,
        ),
      ],
      onError: (_, error, _) => reported.add(error),
    );

    await expectLater(
      server.handle(_request('/')),
      throwsA(same(initializationFailure)),
    );
    expect(
      reported,
      unorderedEquals(<Object>[
        firstCleanupFailure,
        secondCleanupFailure,
        initializationFailure,
      ]),
    );
  });

  test('does not report controlled server outcomes', () async {
    final reported = <Object>[];
    final server = Server(
      routes: const [],
      middleware: <Middleware>[
        (context, next) => switch (context.request.uri.path) {
          '/redirect' => throw Redirect(Uri.parse('/target')),
          '/not-found' => throw const NotFound('Missing'),
          '/http-error' => throw const HttpError(418, 'Expected'),
          '/too-large' => throw const PayloadTooLargeException(8),
          _ => next(),
        },
      ],
      onError: (_, error, _) => reported.add(error),
    );

    for (final expectation in <({String path, int status})>[
      (path: '/redirect', status: 302),
      (path: '/not-found', status: 404),
      (path: '/http-error', status: 418),
      (path: '/too-large', status: 413),
    ]) {
      final response = await server.handle(_request(expectation.path));
      await response.readBytes();
      expect(response.status, expectation.status);
    }
    expect(reported, isEmpty);
  });

  test('rejects strict invalid route search without reporting it', () async {
    final reported = <Object>[];
    var calls = 0;
    final route =
        AppRoute<NoParams, _StrictSearch, NoData>(
          path: '/',
          search: SearchParams<_StrictSearch>.codec(
            keys: const <String>{'page'},
            defaults: (page: 1),
            invalid: InvalidSearchBehavior.error,
            decode: (input) => (page: input.integer('page') ?? 1),
            encode: (value, output) => output.integer('page', value.page),
          ),
        ).server(
          handlers: <HttpMethod, ServerRouteHandler<NoParams, _StrictSearch>>{
            HttpMethod.get: (_) {
              calls++;
              return ServerResponse.text('handled');
            },
          },
        );
    final server = Server(
      routes: <RouteNode>[route],
      onError: (_, error, _) => reported.add(error),
    );

    final response = await server.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/?page=invalid'),
        headers: Headers.single(<String, String>{'accept': 'application/json'}),
      ),
    );
    final body = await response.readText();
    final frame = jsonDecode(body) as Map<String, Object?>;

    expect(response.status, 400, reason: body);
    expect(frame, containsPair('type', 'error'));
    expect(
      frame,
      containsPair('message', 'Search parameter "page" must be an integer.'),
    );
    expect(response.headers.value('vary'), 'Accept');
    expect(body, isNot(contains('page=invalid')));
    expect(calls, 0);
    expect(reported, isEmpty);
  });

  test('still reports a route handler parameter format failure', () async {
    const failure = ParameterFormatException('handler bug');
    final reported = <Object>[];
    final route = AppRoute<NoParams, NoSearch, NoData>(path: '/').server(
      handlers: <HttpMethod, ServerRouteHandler<NoParams, NoSearch>>{
        HttpMethod.get: (_) => throw failure,
      },
    );
    final server = Server(
      routes: <RouteNode>[route],
      onError: (_, error, _) => reported.add(error),
    );

    final response = await server.handle(_request('/'));

    expect(response.status, 500);
    await response.readBytes();
    expect(reported, <Object>[failure]);
  });

  test('still reports a route search encoder format failure', () async {
    const failure = ParameterFormatException('encoder bug');
    final reported = <Object>[];
    var calls = 0;
    final route =
        AppRoute<NoParams, _StrictSearch, NoData>(
          path: '/',
          search: SearchParams<_StrictSearch>.codec(
            keys: const <String>{'page'},
            defaults: (page: 1),
            invalid: InvalidSearchBehavior.error,
            decode: (input) => (page: input.integer('page') ?? 1),
            encode: (_, _) => throw failure,
          ),
        ).server(
          handlers: <HttpMethod, ServerRouteHandler<NoParams, _StrictSearch>>{
            HttpMethod.get: (_) {
              calls++;
              return ServerResponse.text('handled');
            },
          },
        );
    final server = Server(
      routes: <RouteNode>[route],
      onError: (_, error, _) => reported.add(error),
    );

    final response = await server.handle(_request('/'));

    expect(response.status, 500);
    await response.readBytes();
    expect(calls, 0);
    expect(reported, <Object>[failure]);
  });

  test('reports every unexpected nested loader failure once', () async {
    final parentFailure = StateError('parent loader failed');
    final childFailure = StateError('child loader failed');
    final reported = <Object>[];
    final child = AppRoute<NoParams, NoSearch, NoData>(
      path: 'child',
    ).server(load: (_) => throw childFailure);
    final parent = AppRoute<NoParams, NoSearch, NoData>(
      path: '/',
      terminal: false,
      children: <RouteNode>[child],
    ).server(load: (_) => throw parentFailure);
    final server = Server(
      routes: <RouteNode>[parent],
      renderer: (_) => ServerResponse.text('never'),
      onError: (_, error, _) => reported.add(error),
    );

    final response = await server.handle(_request('/child'));

    expect(response.status, 500);
    await response.readBytes();
    expect(reported, unorderedEquals(<Object>[parentFailure, childFailure]));
  });

  test('does not report invalid server function payloads', () async {
    final reported = <Object>[];
    var calls = 0;
    final server = Server(
      routes: const [],
      functions: <String, ServerFunctionBinding>{
        'typed': ServerFunctionBinding(
          ServerFunction<int, int>(
            handler: (context) {
              calls++;
              return context.data;
            },
          ),
        ),
        'iterable': ServerFunctionBinding(
          ServerFunction<Iterable<int>, int>(
            handler: (context) {
              calls++;
              return context.data.length;
            },
          ),
          decodeInput: (value) => (value as List)
              .map((item) => item as int)
              .toList(growable: false),
        ),
      },
      allowRpcWithoutOrigin: true,
      onError: (_, error, _) => reported.add(error),
    );

    for (final body in <String>[
      '{',
      r'{"data":{"$type":"Unknown","$value":1}}',
      '{"data":"not an integer"}',
    ]) {
      final response = await server.handle(_rpcRequest('typed', body: body));
      expect(response.status, 400);
      expect(
        await response.readText(),
        contains('Invalid server function payload'),
      );
    }
    final nested = await server.handle(
      _rpcRequest('iterable', body: '{"data":["not an integer"]}'),
    );
    expect(nested.status, 400);
    await nested.readBytes();
    expect(calls, 0);
    expect(reported, isEmpty);
  });

  test(
    'reports a handler FormatException after valid input decoding',
    () async {
      final failure = const FormatException('handler bug');
      final reported = <Object>[];
      final server = Server(
        routes: const [],
        functions: <String, ServerFunctionBinding>{
          'typed': ServerFunctionBinding(
            ServerFunction<int, int>(handler: (_) => throw failure),
          ),
        },
        allowRpcWithoutOrigin: true,
        onError: (_, error, _) => reported.add(error),
      );

      final response = await server.handle(
        _rpcRequest('typed', body: '{"data":1}'),
      );

      expect(response.status, 500);
      await response.readBytes();
      expect(reported, <Object>[failure]);
    },
  );

  test('does not report a controlled typed frame overflow', () async {
    final reported = <Object>[];
    final server = Server(
      routes: const [],
      functions: <String, ServerFunctionBinding>{
        'large': ServerFunctionBinding(
          ServerFunction<NoServerInput, String>(handler: (_) => 'x' * 1024),
        ),
      },
      allowRpcWithoutOrigin: true,
      maxFunctionResponseFrameBytes: Server.minimumFunctionResponseFrameBytes,
      onError: (_, error, _) => reported.add(error),
    );

    final response = await server.handle(_rpcRequest('large'));

    expect(response.status, 500);
    expect(await response.readText(), '{"version":1,"type":"error"}');
    expect(reported, isEmpty);
  });

  test('does not report a controlled typed stream frame overflow', () async {
    final reported = <Object>[];
    var finalized = false;

    Stream<String> values() async* {
      try {
        yield 'x' * 1024;
        yield 'not sent';
      } finally {
        finalized = true;
      }
    }

    final server = Server(
      routes: const [],
      functions: <String, ServerFunctionBinding>{
        'large-stream': ServerFunctionBinding(
          ServerFunction<NoServerInput, Stream<String>>(
            handler: (_) => values(),
          ),
        ),
      },
      allowRpcWithoutOrigin: true,
      maxFunctionResponseFrameBytes: Server.minimumFunctionResponseFrameBytes,
      onError: (_, error, _) => reported.add(error),
    );

    final response = await server.handle(_rpcRequest('large-stream'));

    expect(await response.readText(), '{"version":1,"type":"error"}\n');
    expect(reported, isEmpty);
    expect(finalized, isTrue);
  });

  test('reports a typed stream failure before its terminal frame', () async {
    final failure = StateError('typed stream failed');
    final reported = <({Object error, StackTrace stackTrace})>[];
    var finalized = false;

    Stream<String> values() async* {
      try {
        yield 'first';
        throw failure;
      } finally {
        finalized = true;
      }
    }

    final server = Server(
      routes: const [],
      functions: <String, ServerFunctionBinding>{
        'stream': ServerFunctionBinding(
          ServerFunction<NoServerInput, Stream<String>>(
            handler: (_) => values(),
          ),
        ),
      },
      allowRpcWithoutOrigin: true,
      onError: (_, error, stackTrace) =>
          reported.add((error: error, stackTrace: stackTrace)),
    );

    final response = await server.handle(_rpcRequest('stream'));
    final lines = const LineSplitter().convert(await response.readText());

    expect(lines, hasLength(2));
    expect(jsonDecode(lines.first), containsPair('data', 'first'));
    expect(jsonDecode(lines.last), containsPair('type', 'error'));
    expect(lines.last, isNot(contains('typed stream failed')));
    expect(reported, hasLength(1));
    expect(reported.single.error, same(failure));
    expect(
      reported.single.stackTrace.toString(),
      contains('error_reporting_test.dart'),
    );
    expect(finalized, isTrue);
  });

  test('reports a raw response stream failure and preserves it', () async {
    final failure = StateError('raw stream failed');
    final reported = <({Object error, StackTrace stackTrace})>[];
    final disposed = Completer<void>();

    Stream<List<int>> body() async* {
      yield const <int>[1];
      throw failure;
    }

    final server = Server(
      routes: const [],
      modules: () => <Module>[_DisposalModule(disposed)],
      middleware: <Middleware>[(_, _) => ServerResponse(body: body())],
      onError: (_, error, stackTrace) =>
          reported.add((error: error, stackTrace: stackTrace)),
    );

    final response = await server.handle(_request('/'));

    await expectLater(response.readBytes(), throwsA(same(failure)));
    await disposed.future;
    expect(reported, hasLength(1));
    expect(reported.single.error, same(failure));
    expect(
      reported.single.stackTrace.toString(),
      contains('error_reporting_test.dart'),
    );
  });

  test('does not report normal downstream response cancellation', () async {
    final reported = <Object>[];
    final cancelled = Completer<void>();
    final disposed = Completer<void>();
    late final StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onListen: () => body.add(const <int>[1]),
      onCancel: cancelled.complete,
    );
    addTearDown(body.close);
    final server = Server(
      routes: const [],
      modules: () => <Module>[_DisposalModule(disposed)],
      middleware: <Middleware>[(_, _) => ServerResponse(body: body.stream)],
      onError: (_, error, _) => reported.add(error),
    );

    final response = await server.handle(_request('/'));
    final firstChunk = Completer<void>();
    final subscription = response.body.listen((_) => firstChunk.complete());
    await firstChunk.future;
    await subscription.cancel();
    await cancelled.future;
    await disposed.future;

    expect(reported, isEmpty);
  });

  test('reports an omitted response body cancellation failure', () async {
    final failure = StateError('response cancellation failed');
    final reported = <Object>[];
    final disposed = Completer<void>();
    final body = StreamController<List<int>>(
      onCancel: () => Future<void>.error(failure),
    );
    addTearDown(body.close);
    final server = Server(
      routes: const [],
      modules: () => <Module>[_DisposalModule(disposed)],
      middleware: <Middleware>[
        (_, _) => ServerResponse(status: 204, body: body.stream),
      ],
      onError: (_, error, _) => reported.add(error),
    );

    final response = await server.handle(_request('/'));

    expect(response.status, 204);
    expect(await response.readBytes(), isEmpty);
    await disposed.future;
    expect(reported, <Object>[failure]);
  });

  test(
    'keeps an asynchronous reporter alive without delaying response',
    () async {
      final failure = StateError('request failed');
      final reporterStarted = Completer<void>();
      final releaseReporter = Completer<void>();
      final disposed = Completer<void>();
      final server = Server(
        routes: const [],
        modules: () => <Module>[_DisposalModule(disposed)],
        middleware: <Middleware>[(_, _) => throw failure],
        onError: (_, _, _) async {
          reporterStarted.complete();
          await releaseReporter.future;
        },
      );

      final response = await server.handle(_request('/'));
      expect(response.status, 500);
      await response.readBytes();
      await reporterStarted.future;
      expect(disposed.isCompleted, isFalse);

      releaseReporter.complete();
      await disposed.future;
    },
  );

  test('uses the current Zone as the default reporter', () async {
    final failure = StateError('default reporter failed');
    final printed = <String>[];

    await runZoned(
      () async {
        final server = Server(
          routes: const [],
          middleware: <Middleware>[(_, _) => throw failure],
        );
        final response = await server.handle(_request('/?secret=query'));
        expect(response.status, 500);
        await response.readBytes();
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed, hasLength(1));
    expect(printed.single, contains('Unexpected Odroe server error'));
    expect(printed.single, contains('GET /'));
    expect(printed.single, isNot(contains('secret=query')));
    expect(printed.single, contains('default reporter failed'));
    expect(printed.single, contains('error_reporting_test.dart'));
  });

  test(
    'a synchronously failing reporter cannot replace the response',
    () async {
      final failure = StateError('request failed');
      final reporterFailure = StateError('reporter failed');
      final printed = <String>[];
      var calls = 0;

      await runZoned(
        () async {
          final server = Server(
            routes: const [],
            middleware: <Middleware>[(_, _) => throw failure],
            onError: (_, _, _) {
              calls++;
              throw reporterFailure;
            },
          );
          final response = await server.handle(_request('/'));
          final body = await response.readText();
          expect(response.status, 500, reason: body);
          expect(body, isNot(contains('request failed')));
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(line),
        ),
      );

      expect(calls, 1);
      expect(printed, hasLength(2));
      expect(printed.first, contains('request failed'));
      expect(printed.last, contains('Odroe Server.onError failed'));
      expect(printed.last, contains('reporter failed'));
    },
  );

  test('an asynchronously failing reporter falls back to the Zone', () async {
    final failure = StateError('async request failed');
    final reporterFailure = StateError('async reporter failed');
    final printed = <String>[];
    final fallbackCompleted = Completer<void>();

    await runZoned(
      () async {
        final server = Server(
          routes: const [],
          middleware: <Middleware>[(_, _) => throw failure],
          onError: (_, _, _) async {
            await Future<void>.value();
            throw reporterFailure;
          },
        );
        final response = await server.handle(_request('/'));
        expect(response.status, 500);
        await response.readBytes();
        await fallbackCompleted.future;
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) {
          printed.add(line);
          if (line.contains('Odroe Server.onError failed')) {
            fallbackCompleted.complete();
          }
        },
      ),
    );

    expect(printed, hasLength(2));
    expect(printed.first, contains('async request failed'));
    expect(printed.last, contains('async reporter failed'));
  });
}

Future<ServerResponse> _middlewareFailure(
  ServerErrorHandler onError,
  Object failure,
) => Server(
  routes: const [],
  middleware: <Middleware>[(_, _) => throw failure],
  onError: onError,
).handle(_request('/'));

Future<ServerResponse> _routeHandlerFailure(
  ServerErrorHandler onError,
  Object failure,
) {
  final route = AppRoute<NoParams, NoSearch, NoData>(path: '/').server(
    handlers: <HttpMethod, ServerRouteHandler<NoParams, NoSearch>>{
      HttpMethod.get: (_) => throw failure,
    },
  );
  return Server(
    routes: <RouteNode>[route],
    onError: onError,
  ).handle(_request('/'));
}

Future<ServerResponse> _loaderFailure(
  ServerErrorHandler onError,
  Object failure,
) {
  final route = AppRoute<NoParams, NoSearch, NoData>(
    path: '/',
  ).server(load: (_) => throw failure);
  return Server(
    routes: <RouteNode>[route],
    renderer: (_) => ServerResponse.text('never'),
    onError: onError,
  ).handle(_request('/'));
}

Future<ServerResponse> _rendererFailure(
  ServerErrorHandler onError,
  Object failure,
) => Server(
  routes: <RouteNode>[AppRoute<NoParams, NoSearch, NoData>(path: '/')],
  renderer: (_) => throw failure,
  onError: onError,
).handle(_request('/'));

Future<ServerResponse> _functionFailure(
  ServerErrorHandler onError,
  Object failure,
) => Server(
  routes: const [],
  functions: <String, ServerFunctionBinding>{
    'failure': ServerFunctionBinding(
      ServerFunction<NoServerInput, String>(handler: (_) => throw failure),
    ),
  },
  allowRpcWithoutOrigin: true,
  onError: onError,
).handle(_rpcRequest('failure'));

Future<ServerResponse> _serializationFailure(
  ServerErrorHandler onError,
  Object failure,
) => Server(
  routes: const [],
  functions: <String, ServerFunctionBinding>{
    'serialize': ServerFunctionBinding(
      ServerFunction<NoServerInput, _SerializedValue>(
        handler: (_) => const _SerializedValue(),
      ),
    ),
  },
  serializer: Serializer(
    adapters: <SerializationAdapter<dynamic>>[_ThrowingAdapter(failure)],
  ),
  allowRpcWithoutOrigin: true,
  onError: onError,
).handle(_rpcRequest('serialize'));

ServerRequest _request(String path) => ServerRequest.bytes(
  method: HttpMethod.get,
  uri: Uri.parse('http://localhost$path'),
);

ServerRequest _rpcRequest(String id, {String body = '{"data":null}'}) =>
    ServerRequest.bytes(
      method: HttpMethod.post,
      uri: Uri.parse('http://localhost/__odroe/functions/$id'),
      headers: Headers.single(<String, String>{
        'content-type': 'application/json; charset=utf-8',
        'x-odroe-server-function': 'true',
      }),
      body: utf8.encode(body),
    );

enum _ModuleFailurePhase { factory, register, initialize }

final class _FailingModule extends Module {
  const _FailingModule(this.phase, this.failure, {this.disposeFailure});

  final _ModuleFailurePhase phase;
  final Object failure;
  final Object? disposeFailure;

  @override
  void register(ModuleRegistry registry) {
    if (phase == _ModuleFailurePhase.register) throw failure;
  }

  @override
  void initialize(AppContext context) {
    if (phase == _ModuleFailurePhase.initialize) throw failure;
  }

  @override
  void dispose(AppContext context) {
    final error = disposeFailure;
    if (error != null) throw error;
  }
}

final class _DisposalModule extends Module {
  const _DisposalModule(this.disposed);

  final Completer<void> disposed;

  @override
  void register(ModuleRegistry registry) {}

  @override
  void dispose(AppContext context) => disposed.complete();
}

final class _CleanupFailureModule extends Module {
  const _CleanupFailureModule(this.failure);

  final Object failure;

  @override
  void register(ModuleRegistry registry) {}

  @override
  void dispose(AppContext context) => throw failure;
}

final class _SerializedValue {
  const _SerializedValue();
}

final class _ThrowingAdapter implements SerializationAdapter<_SerializedValue> {
  const _ThrowingAdapter(this.failure);

  final Object failure;

  @override
  String get tag => 'SerializedValue';

  @override
  bool canEncode(Object value) => value is _SerializedValue;

  @override
  Object? encode(_SerializedValue value, Serializer serializer) {
    throw failure;
  }

  @override
  _SerializedValue decode(Object? value, Serializer serializer) =>
      const _SerializedValue();
}
