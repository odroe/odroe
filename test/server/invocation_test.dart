import 'dart:async';
import 'dart:convert';

import 'package:odroe/odroe.dart';
import 'package:odroe/server.dart';
import 'package:test/test.dart';

final _valueKey = ContextKey<int>('invocation.value');

final class _Bindings {
  const _Bindings(this.value);

  final int value;
}

final class _ValueModule extends Module {
  const _ValueModule(this.value);

  final int value;

  @override
  void register(ModuleRegistry registry) {
    _valueKey.provide(registry, value);
  }
}

final class _LifecycleModule extends Module {
  _LifecycleModule(this.name, this.events, {this.disposed, this.disposeError});

  final String name;
  final List<String> events;
  final Completer<void>? disposed;
  final Object? disposeError;

  @override
  void register(ModuleRegistry registry) {}

  @override
  void dispose(AppContext context) {
    events.add('dispose:$name');
    disposed?.complete();
    final error = disposeError;
    if (error != null) throw error;
  }
}

void main() {
  test('legacy handlers track tasks without adapter modules', () async {
    final events = <String>[];
    final outerGate = Completer<void>();
    final nestedStarted = Completer<void>();
    final nestedGate = Completer<void>();
    final disposed = Completer<void>();
    late ServerInvocation seen;
    var invocationModuleCalls = 0;
    final server = Server(
      routes: const [],
      modules: () => <Module>[
        _LifecycleModule('base', events, disposed: disposed),
      ],
      invocationModules: (_) {
        invocationModuleCalls++;
        return const <Module>[];
      },
      middleware: [
        (context, _) {
          seen = context.invocation;
          context.invocation.waitUntil(() async {
            await outerGate.future;
            context.invocation.waitUntil(nestedGate.future);
            nestedStarted.complete();
          }());
          return ServerResponse.text('ok');
        },
      ],
    );
    final ServerHandler handler = server.handler;

    final response = await handler(_request(0));

    expect(await response.readText(), 'ok');
    expect(identical(seen, ServerInvocation.empty), isFalse);
    expect(seen.bindings, isNull);
    expect(seen.supportsWaitUntil, isFalse);
    expect(invocationModuleCalls, 0);
    expect(events, isEmpty);

    outerGate.complete();
    await nestedStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);

    nestedGate.complete();
    await disposed.future;
    expect(events, <String>['dispose:base']);
  });

  test(
    'isolates bindings and invocation modules across 128 requests',
    () async {
      final server = Server(
        routes: const [],
        invocationModules: (invocation) => <Module>[
          _ValueModule(invocation.requireBindings<_Bindings>().value),
        ],
        middleware: [
          (context, _) async {
            final expected = context.invocation
                .requireBindings<_Bindings>()
                .value;
            await Future<void>.delayed(
              Duration(microseconds: (127 - expected) % 7),
            );
            expect(context.read(_valueKey), expected);
            expect(
              context.invocation.requireBindings<_Bindings>().value,
              expected,
            );
            return ServerResponse.text('$expected');
          },
        ],
      );
      final ServerInvocationHandler handler = server.invocationHandler;

      final values = await Future.wait<int>(
        List<Future<int>>.generate(128, (id) async {
          final scheduled = <Future<void>>[];
          final response = await handler(
            _request(id),
            ServerInvocation(bindings: _Bindings(id), waitUntil: scheduled.add),
          );
          final value = int.parse(await response.readText());
          await Future.wait<void>(scheduled);
          return value;
        }),
      );

      expect(values, List<int>.generate(128, (id) => id));
    },
  );

  test('keeps modules until the response body finishes', () async {
    final events = <String>[];
    final taskGate = Completer<void>();
    final bodyStarted = Completer<void>();
    final bodyGate = Completer<void>();
    final server = Server(
      routes: const [],
      modules: () => <Module>[_LifecycleModule('base', events)],
      middleware: [
        (context, _) {
          context.invocation.waitUntil(taskGate.future);

          Stream<List<int>> body() async* {
            bodyStarted.complete();
            yield utf8.encode('ok');
            await bodyGate.future;
          }

          return ServerResponse(body: body());
        },
      ],
    );
    final scheduled = <Future<void>>[];
    final response = await server.handleInvocation(
      _request(0),
      ServerInvocation(waitUntil: scheduled.add),
    );
    final body = response.readText();
    await bodyStarted.future;

    taskGate.complete();
    await scheduled.first;
    await Future<void>.delayed(Duration.zero);
    expect(events, isNot(contains('dispose:base')));

    bodyGate.complete();
    expect(await body, 'ok');
    await scheduled[1];
    expect(events, <String>['dispose:base']);
  });

  test('cancels omitted response bodies before disposing modules', () async {
    for (final scenario in <({HttpMethod method, int status})>[
      (method: HttpMethod.head, status: 200),
      (method: HttpMethod.get, status: 204),
      (method: HttpMethod.get, status: 205),
      (method: HttpMethod.get, status: 304),
    ]) {
      final events = <String>[];
      final server = Server(
        routes: const [],
        modules: () => <Module>[_LifecycleModule('base', events)],
        middleware: [
          (context, _) {
            Stream<List<int>> body() async* {
              try {
                yield utf8.encode('must not be sent');
              } finally {
                events.add('body:cancel');
              }
            }

            return ServerResponse(status: scenario.status, body: body());
          },
        ],
      );
      final scheduled = <Future<void>>[];

      final response = await server.handleInvocation(
        _request(0, method: scenario.method),
        ServerInvocation(waitUntil: scheduled.add),
      );

      expect(await response.readText(), isEmpty);
      await Future.wait<void>(scheduled);
      expect(events, <String>['body:cancel', 'dispose:base']);
    }
  });

  test(
    'returns the response before nested tasks finish and disposes last',
    () async {
      final events = <String>[];
      final bodyStarted = Completer<void>();
      final bodyGate = Completer<void>();
      final outerStarted = Completer<void>();
      final outerGate = Completer<void>();
      final nestedStarted = Completer<void>();
      final nestedGate = Completer<void>();
      final server = Server(
        routes: const [],
        modules: () => <Module>[_LifecycleModule('base', events)],
        invocationModules: (_) => <Module>[
          _LifecycleModule('invocation', events),
        ],
        middleware: [
          (context, _) {
            context.invocation.waitUntil(() async {
              events.add('outer:start');
              outerStarted.complete();
              await outerGate.future;
              events.add('outer:resume');
              context.invocation.waitUntil(() async {
                events.add('nested:start');
                nestedStarted.complete();
                await nestedGate.future;
                events.add('nested:end');
              }());
              events.add('outer:end');
            }());

            Stream<List<int>> body() async* {
              events.add('body:start');
              bodyStarted.complete();
              yield utf8.encode('ok');
              await bodyGate.future;
              events.add('body:end');
            }

            return ServerResponse(body: body());
          },
        ],
      );
      final scheduled = <Future<void>>[];
      final invocation = ServerInvocation(waitUntil: scheduled.add);

      final response = await server.handleInvocation(_request(0), invocation);
      events.add('response:return');
      await outerStarted.future;

      expect(events, contains('response:return'));
      expect(events, isNot(contains('dispose:invocation')));
      expect(scheduled, hasLength(2));
      final cleanup = scheduled[1];

      final body = response.readText();
      await bodyStarted.future;
      expect(events, isNot(contains('dispose:invocation')));

      bodyGate.complete();
      expect(await body, 'ok');
      expect(events, isNot(contains('dispose:invocation')));

      outerGate.complete();
      await nestedStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(events, isNot(contains('dispose:invocation')));

      nestedGate.complete();
      await cleanup;

      expect(
        events,
        containsAllInOrder(<String>[
          'outer:start',
          'response:return',
          'body:start',
          'body:end',
          'outer:resume',
          'nested:start',
          'outer:end',
          'nested:end',
          'dispose:invocation',
          'dispose:base',
        ]),
      );
      expect(scheduled, hasLength(3));
    },
  );

  test('reports a background failure without a host lifetime', () async {
    final reported = Completer<Object>();
    final server = Server(
      routes: const [],
      middleware: [
        (context, _) {
          context.invocation.waitUntil(
            Future<void>.error(StateError('background failed')),
          );
          return ServerResponse.text('ok');
        },
      ],
    );
    final invocation = ServerInvocation(
      onError: (error, _) {
        if (!reported.isCompleted) reported.complete(error);
      },
    );

    final response = await server.handleInvocation(_request(0), invocation);

    expect(await response.readText(), 'ok');
    expect(await reported.future, isA<StateError>());
  });

  test('reports a dispose failure without an uncaught future', () async {
    final reported = Completer<Object>();
    final server = Server(
      routes: const [],
      modules: () => <Module>[
        _LifecycleModule(
          'failing',
          <String>[],
          disposeError: StateError('dispose failed'),
        ),
      ],
      middleware: [(context, _) => ServerResponse.text('ok')],
    );
    final invocation = ServerInvocation(
      onError: (error, _) {
        if (!reported.isCompleted) reported.complete(error);
      },
    );

    final response = await server.handleInvocation(_request(0), invocation);

    expect(await response.readText(), 'ok');
    expect(await reported.future, isA<StateError>());
  });

  test('falls back to observed cleanup when host waitUntil throws', () async {
    final reported = Completer<Object>();
    final disposed = Completer<void>();
    final server = Server(
      routes: const [],
      modules: () => <Module>[
        _LifecycleModule('base', <String>[], disposed: disposed),
      ],
      middleware: [(context, _) => ServerResponse.text('ok')],
    );
    final invocation = ServerInvocation(
      waitUntil: (_) => throw StateError('host waitUntil failed'),
      onError: (error, _) {
        if (!reported.isCompleted) reported.complete(error);
      },
    );

    final response = await server.handleInvocation(_request(0), invocation);

    expect(await response.readText(), 'ok');
    expect(await reported.future, isA<StateError>());
    await disposed.future;
  });

  test('keeps task rejections on the host waitUntil channel', () async {
    final scheduled = <Future<void>>[];
    final reported = <Object>[];
    final server = Server(
      routes: const [],
      middleware: [
        (context, _) {
          context.invocation.waitUntil(
            Future<void>.error(StateError('host task failed')),
          );
          return ServerResponse.text('ok');
        },
      ],
    );
    final invocation = ServerInvocation(
      waitUntil: scheduled.add,
      onError: (error, _) => reported.add(error),
    );

    final response = await server.handleInvocation(_request(0), invocation);
    expect(await response.readText(), 'ok');

    await expectLater(scheduled.first, throwsA(isA<StateError>()));
    await scheduled.last;
    expect(reported, isEmpty);
  });

  test(
    'close drains started work then releases the application once',
    () async {
      final events = <String>[];
      final bodyStarted = Completer<void>();
      final bodyGate = Completer<void>();
      final taskStarted = Completer<void>();
      final taskGate = Completer<void>();
      var closeCalls = 0;
      final server = Server(
        routes: const [],
        modules: () => <Module>[_LifecycleModule('request', events)],
        middleware: [
          (context, _) {
            context.invocation.waitUntil(() async {
              events.add('task:start');
              taskStarted.complete();
              await taskGate.future;
              events.add('task:end');
            }());

            Stream<List<int>> body() async* {
              events.add('body:start');
              bodyStarted.complete();
              yield utf8.encode('ok');
              await bodyGate.future;
              events.add('body:end');
            }

            return ServerResponse(body: body());
          },
        ],
        onClose: () {
          closeCalls++;
          events.add('application:close');
        },
      );

      final response = await server.handle(_request(0));
      final body = response.readText();
      await Future.wait<void>(<Future<void>>[
        bodyStarted.future,
        taskStarted.future,
      ]);

      final firstClose = server.close();
      final secondClose = server.close();
      expect(secondClose, same(firstClose));
      expect(closeCalls, 0);
      await expectLater(server.handle(_request(1)), throwsA(isA<StateError>()));

      bodyGate.complete();
      expect(await body, 'ok');
      await Future<void>.delayed(Duration.zero);
      expect(closeCalls, 0);

      taskGate.complete();
      await firstClose;

      expect(events, <String>[
        'task:start',
        'body:start',
        'body:end',
        'task:end',
        'dispose:request',
        'application:close',
      ]);
      expect(closeCalls, 1);
      expect(server.close(), same(firstClose));
    },
  );

  test('close preserves one application cleanup failure', () async {
    final failure = StateError('application close failed');
    var closeCalls = 0;
    final server = Server(
      routes: const [],
      onClose: () {
        closeCalls++;
        throw failure;
      },
    );

    final firstClose = server.close();
    final secondClose = server.close();

    expect(secondClose, same(firstClose));
    await expectLater(firstClose, throwsA(same(failure)));
    expect(server.close(), same(firstClose));
    expect(closeCalls, 1);
  });

  test('a response construction failure still disposes before close', () async {
    final events = <String>[];
    final server = Server(
      routes: const [],
      exposeErrors: true,
      modules: () => <Module>[_LifecycleModule('request', events)],
      middleware: [(context, _) => throw const _BadToString()],
      onError: (_, _, _) {},
      onClose: () => events.add('application:close'),
    );

    await expectLater(server.handle(_request(0)), throwsA(isA<StateError>()));
    await server.close();

    expect(events, <String>['dispose:request', 'application:close']);
  });

  test(
    'an invocation module factory failure disposes yielded base modules',
    () async {
      final failure = StateError('invocation modules failed');
      final events = <String>[];
      final server = Server(
        routes: const [],
        modules: () => <Module>[_LifecycleModule('base', events)],
        invocationModules: (_) => throw failure,
        onError: (_, _, _) {},
      );

      await expectLater(
        server.handleInvocation(_request(0), ServerInvocation()),
        throwsA(same(failure)),
      );
      await server.close();

      expect(events, <String>['dispose:base']);
    },
  );

  test('rejects empty and repeated invocations', () async {
    final server = Server(
      routes: const [],
      middleware: [(context, _) => ServerResponse.text('ok')],
    );

    await expectLater(
      server.handleInvocation(_request(0), ServerInvocation.empty),
      throwsA(isA<StateError>()),
    );

    final scheduled = <Future<void>>[];
    final invocation = ServerInvocation(waitUntil: scheduled.add);
    final response = await server.handleInvocation(_request(1), invocation);
    expect(await response.readText(), 'ok');
    await Future.wait<void>(scheduled);

    await expectLater(
      server.handleInvocation(_request(2), invocation),
      throwsA(isA<StateError>()),
    );
  });
}

ServerRequest _request(int id, {HttpMethod method = HttpMethod.get}) =>
    ServerRequest.bytes(method: method, uri: Uri.parse('http://localhost/$id'));

final class _BadToString {
  const _BadToString();

  @override
  String toString() => throw StateError('toString failed');
}
