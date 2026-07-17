import 'dart:async';
import 'dart:typed_data';

import 'package:odroe/start.dart';
import 'package:test/test.dart';

void main() {
  test('serializer preserves typed bytes and protocol-shaped maps', () {
    final serializer = StartSerializer();
    final bytes = Uint8List.fromList(<int>[1, 2, 255]);
    final reserved = <String, Object?>{
      r'$type': 'user-value',
      r'$value': <String, Object?>{'nested': true},
    };

    expect(serializer.decodeJson(serializer.encodeJson(bytes)), bytes);
    expect(serializer.decodeJson(serializer.encodeJson(reserved)), reserved);
  });

  test(
    'typed RPC executes middleware and server implementation in memory',
    () async {
      const requestId = StartContextKey<String>('requestId');
      final function =
          ServerFunction<Map<String, Object?>, Map<String, Object?>>(
            middleware: <StartMiddleware>[
              (context, next) {
                context.set(requestId, 'req-1');
                return next();
              },
            ],
            handler: (context) => <String, Object?>{
              'hello': context.data['name'],
              'requestId': context.request.require(requestId),
            },
          );
      final app = StartApplication(
        routes: <AnyAppRoute>[AppRoute<NoParams, NoSearch, NoData>(path: '/')],
        functions: <String, AnyServerFunction>{'greet': function},
      );
      final client = StartRpcClient(
        baseUri: Uri.parse('http://localhost:3000'),
        transport: InMemoryStartTransport(app.handle),
      );

      final result =
          await ServerFunctionRef<Map<String, Object?>, Map<String, Object?>>(
            id: 'greet',
          ).call(client, <String, Object?>{'name': 'Odroe'});

      expect(result, <String, Object?>{'hello': 'Odroe', 'requestId': 'req-1'});
    },
  );

  test(
    'RPC transports redirect, not-found, errors, and streams distinctly',
    () async {
      final app = StartApplication(
        routes: <AnyAppRoute>[AppRoute<NoParams, NoSearch, NoData>(path: '/')],
        functions: <String, AnyServerFunction>{
          'redirect': ServerFunction<NoServerInput, void>(
            handler: (_) =>
                throw StartRedirect(Uri.parse('/login'), status: 307),
          ),
          'missing': ServerFunction<NoServerInput, void>(
            handler: (_) => throw const StartNotFound('Post missing'),
          ),
          'failed': ServerFunction<NoServerInput, void>(
            handler: (_) => throw StateError('secret details'),
          ),
          'numbers': ServerFunction<NoServerInput, Stream<int>>(
            handler: (_) => Stream<int>.fromIterable(<int>[1, 2, 3]),
          ),
        },
      );
      final client = StartRpcClient(
        baseUri: Uri.parse('http://localhost'),
        transport: InMemoryStartTransport(app.handle),
      );
      const input = NoServerInput();

      await expectLater(
        const ServerFunctionRef<NoServerInput, void>(
          id: 'redirect',
        ).call(client, input),
        throwsA(isA<StartRedirect>()),
      );
      await expectLater(
        const ServerFunctionRef<NoServerInput, void>(
          id: 'missing',
        ).call(client, input),
        throwsA(isA<StartNotFound>()),
      );
      await expectLater(
        const ServerFunctionRef<NoServerInput, void>(
          id: 'failed',
        ).call(client, input),
        throwsA(
          isA<RemoteServerException>().having(
            (error) => error.message,
            'message',
            'Internal server error.',
          ),
        ),
      );
      final stream = await const ServerStreamFunctionRef<NoServerInput, int>(
        id: 'numbers',
      ).call(client, input);
      expect(await stream.toList(), <int>[1, 2, 3]);
    },
  );

  test(
    'GET server functions reject method mismatches before parsing',
    () async {
      final app = StartApplication(
        routes: <AnyAppRoute>[AppRoute<NoParams, NoSearch, NoData>(path: '/')],
        functions: <String, AnyServerFunction>{
          'read': ServerFunction<NoServerInput, int>(
            method: StartMethod.get,
            handler: (_) => 1,
          ),
        },
      );
      final response = await app.handle(
        StartRequest.bytes(
          method: StartMethod.post,
          uri: Uri.parse('http://localhost/__odroe/functions/read'),
          headers: StartHeaders.single(<String, String>{
            'origin': 'http://localhost',
          }),
        ),
      );
      expect(response.status, 405);
      expect(response.headers.value('allow'), 'GET');
    },
  );
}
