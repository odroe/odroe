import 'dart:convert';
import 'dart:typed_data';

import 'package:odroe/server.dart';
import 'package:test/test.dart';

void main() {
  test('matches exactly one encoded function id segment', () async {
    var calls = 0;
    final function = ServerFunction<NoServerInput, int>(
      handler: (_) => ++calls,
    );
    final server = Server(
      routes: const [],
      functions: <String, ServerFunctionBinding>{
        'read': ServerFunctionBinding(function),
        'team/read': ServerFunctionBinding(function),
      },
      allowRpcWithoutOrigin: true,
    );

    final exact = await server.handle(_request('/__odroe/functions/read'));
    expect(exact.status, 200);
    expect(jsonDecode(await exact.readText()), containsPair('data', 1));

    for (final path in <String>[
      '/__odroe/functions',
      '/__odroe/functions/',
      '/__odroe/functions/read/extra',
    ]) {
      final response = await server.handle(_request(path));
      expect(response.status, 404, reason: path);
      expect(
        jsonDecode(await response.readText()),
        containsPair('type', 'notFound'),
        reason: path,
      );
    }
    expect(calls, 1);

    final encoded = await server.handle(
      _request('/__odroe/functions/team%2Fread'),
    );
    expect(encoded.status, 200);
    expect(jsonDecode(await encoded.readText()), containsPair('data', 2));
    expect(calls, 2);
  });

  test('validates server function payload and response budgets', () {
    final server = Server(routes: const []);
    expect(server.maxFunctionPayload, Server.defaultMaxFunctionPayload);
    expect(
      server.maxFunctionResponseFrameBytes,
      Server.defaultMaxFunctionResponseFrameBytes,
    );

    for (final maxBytes in <int>[0, -1]) {
      expect(
        () => Server(routes: const [], maxFunctionPayload: maxBytes),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.invalidValue,
            'invalidValue',
            maxBytes,
          ),
        ),
      );
    }
    expect(
      () => Server(
        routes: const [],
        maxFunctionResponseFrameBytes:
            Server.minimumFunctionResponseFrameBytes - 1,
      ),
      throwsArgumentError,
    );
    expect(
      Server(
        routes: const [],
        maxFunctionResponseFrameBytes: Server.minimumFunctionResponseFrameBytes,
      ).maxFunctionResponseFrameBytes,
      Server.minimumFunctionResponseFrameBytes,
    );
  });

  test('encodes value and stream outputs before serialization', () async {
    var encodes = 0;
    Object? encodePost(Object? value) {
      encodes++;
      final post = value as _Post;
      return <String, Object?>{'id': post.id, 'title': post.title};
    }

    final server = Server(
      routes: const [],
      functions: <String, ServerFunctionBinding>{
        'read': ServerFunctionBinding(
          ServerFunction<NoServerInput, _Post>(
            handler: (_) => (id: 42, title: 'Odroe'),
          ),
          encodeOutput: encodePost,
        ),
        'watch': ServerFunctionBinding(
          ServerFunction<NoServerInput, Stream<_Post>>(
            handler: (_) => Stream<_Post>.fromIterable(const <_Post>[
              (id: 43, title: 'Native'),
              (id: 44, title: 'Edge'),
            ]),
          ),
          encodeOutput: encodePost,
        ),
        'empty': ServerFunctionBinding(
          ServerFunction<NoServerInput, _Post>(
            handler: (_) => (id: 45, title: 'Hidden'),
          ),
          encodeOutput: (_) => null,
        ),
      },
      allowRpcWithoutOrigin: true,
    );

    final value = await server.handle(_request('/__odroe/functions/read'));
    expect(jsonDecode(await value.readText()), <String, Object?>{
      'version': 1,
      'type': 'data',
      'data': <String, Object?>{'id': 42, 'title': 'Odroe'},
    });

    final streamed = await server.handle(_request('/__odroe/functions/watch'));
    final lines = const LineSplitter().convert(await streamed.readText());
    expect(lines.map(jsonDecode), <Object?>[
      <String, Object?>{
        'version': 1,
        'type': 'data',
        'data': <String, Object?>{'id': 43, 'title': 'Native'},
      },
      <String, Object?>{
        'version': 1,
        'type': 'data',
        'data': <String, Object?>{'id': 44, 'title': 'Edge'},
      },
    ]);

    final empty = await server.handle(_request('/__odroe/functions/empty'));
    expect(jsonDecode(await empty.readText()), containsPair('data', null));
    expect(encodes, 3);
  });

  test('keeps output encoder failures on the server error path', () async {
    final failure = StateError('Cannot encode output.');
    final reported = <Object>[];
    final server = Server(
      routes: const [],
      functions: <String, ServerFunctionBinding>{
        'read': ServerFunctionBinding(
          ServerFunction<NoServerInput, String>(handler: (_) => 'value'),
          encodeOutput: (_) => throw failure,
        ),
        'watch': ServerFunctionBinding(
          ServerFunction<NoServerInput, Stream<String>>(
            handler: (_) => Stream<String>.value('value'),
          ),
          encodeOutput: (_) => throw failure,
        ),
      },
      allowRpcWithoutOrigin: true,
      onError: (_, error, _) => reported.add(error),
    );

    final value = await server.handle(_request('/__odroe/functions/read'));
    expect(value.status, 500);
    expect(jsonDecode(await value.readText()), containsPair('type', 'error'));

    final streamed = await server.handle(_request('/__odroe/functions/watch'));
    expect(streamed.status, 200);
    expect(
      jsonDecode(
        (const LineSplitter().convert(await streamed.readText())).single,
      ),
      containsPair('type', 'error'),
    );
    expect(reported, <Object>[failure, failure]);
  });

  test('counts the complete value frame in UTF-8 bytes', () async {
    const value = '雪🙂';
    final expected = JsonUtf8Encoder().convert(<String, Object?>{
      'version': 1,
      'type': 'data',
      'data': value,
    });
    final exact = _server<String>(
      maxResponseBytes: expected.length,
      handler: (_) => value,
    );

    final exactResponse = await exact.handle(_request());
    expect(exactResponse.status, 200);
    expect(await exactResponse.readBytes(), expected);
    expect(exactResponse.headers.value('content-length'), '${expected.length}');

    final limited = _server<String>(
      maxResponseBytes: expected.length - 1,
      handler: (_) => value,
    );
    final limitedResponse = await limited.handle(_request());
    final limitedBytes = await limitedResponse.readBytes();
    expect(limitedResponse.status, 500);
    expect(limitedBytes.length, lessThanOrEqualTo(expected.length - 1));
    expect(
      jsonDecode(utf8.decode(limitedBytes)),
      containsPair('type', 'error'),
    );
  });

  test('uses the minimal error frame at the minimum budget', () async {
    final oversized = _server<String>(
      maxResponseBytes: Server.minimumFunctionResponseFrameBytes,
      handler: (_) => 'too large',
    );
    final oversizedResponse = await oversized.handle(_request());
    expect(oversizedResponse.status, 500);
    expect(await oversizedResponse.readText(), '{"version":1,"type":"error"}');

    final exposedFailure = _server<String>(
      maxResponseBytes: Server.minimumFunctionResponseFrameBytes,
      exposeErrors: true,
      handler: (_) => throw StateError('x' * 1024),
    );
    final failureResponse = await exposedFailure.handle(_request());
    expect(failureResponse.status, 500);
    expect(await failureResponse.readText(), '{"version":1,"type":"error"}');
  });

  test('bounds an oversized RPC redirect inside its catch path', () async {
    final server = _server<Never>(
      maxResponseBytes: Server.minimumFunctionResponseFrameBytes,
      handler: (_) =>
          throw Redirect(Uri.parse('https://example.com/${'x' * 1024}')),
    );

    final response = await server.handle(_request());
    expect(response.status, 500);
    expect(await response.readText(), '{"version":1,"type":"error"}');
  });

  test(
    'limits each stream frame and cancels after an oversized item',
    () async {
      const firstValue = '雪';
      final firstFrame = JsonUtf8Encoder().convert(<String, Object?>{
        'version': 1,
        'type': 'data',
        'data': firstValue,
      });
      var finalized = false;

      Stream<String> values() async* {
        try {
          yield firstValue;
          yield List<String>.filled(100, firstValue).join();
          yield 'not sent';
        } finally {
          finalized = true;
        }
      }

      final server = _server<Stream<String>>(
        maxResponseBytes: firstFrame.length,
        handler: (_) => values(),
      );
      final response = await server.handle(_request());
      final chunks = await response.body.toList();
      final lines = const LineSplitter().convert(
        utf8.decode(chunks.expand((chunk) => chunk).toList(growable: false)),
      );

      expect(chunks, hasLength(2));
      expect(chunks.every((chunk) => chunk.last == 0x0a), isTrue);
      expect(lines, hasLength(2));
      expect(jsonDecode(lines.first), containsPair('data', firstValue));
      expect(jsonDecode(lines.last), containsPair('type', 'error'));
      for (final line in lines) {
        expect(utf8.encode(line).length, lessThanOrEqualTo(firstFrame.length));
      }
      expect(finalized, isTrue);
    },
  );

  test('does not cap cumulative stream bytes', () async {
    const value = '雪';
    final frame = JsonUtf8Encoder().convert(<String, Object?>{
      'version': 1,
      'type': 'data',
      'data': value,
    });
    final server = _server<Stream<String>>(
      maxResponseBytes: frame.length,
      handler: (_) => Stream<String>.fromIterable(const <String>[value, value]),
    );

    final response = await server.handle(_request());
    final chunks = await response.body.toList();
    final lines = const LineSplitter().convert(
      utf8.decode(chunks.expand((chunk) => chunk).toList(growable: false)),
    );
    expect(chunks, hasLength(2));
    expect(lines, hasLength(2));
    expect(
      lines.every((line) => utf8.encode(line).length == frame.length),
      isTrue,
    );
  });

  test('returns exact backing storage for a full-size stream frame', () async {
    final emptyFrameBytes = JsonUtf8Encoder().convert(<String, Object?>{
      'version': 1,
      'type': 'data',
      'data': '',
    }).length;
    final value =
        'x' * (Server.defaultMaxFunctionResponseFrameBytes - emptyFrameBytes);
    final server = _server<Stream<String>>(
      maxResponseBytes: Server.defaultMaxFunctionResponseFrameBytes,
      handler: (_) => Stream<String>.value(value),
    );

    final response = await server.handle(_request());
    final chunks = await response.body.toList();
    expect(chunks, hasLength(1));
    final bytes = chunks.single as Uint8List;
    expect(bytes.length, Server.defaultMaxFunctionResponseFrameBytes + 1);
    expect(bytes.buffer.lengthInBytes, bytes.lengthInBytes);
    expect(bytes.last, 0x0a);
  });

  test('serializes an oversized value only once', () async {
    final adapter = _CountingAdapter();
    final server = _server<_AdaptedValue>(
      maxResponseBytes: 64,
      serializer: Serializer(
        adapters: <SerializationAdapter<dynamic>>[adapter],
      ),
      handler: (_) => const _AdaptedValue(),
    );

    final response = await server.handle(_request());
    await response.readBytes();
    expect(response.status, 500);
    expect(adapter.encodes, 1);
  });

  test(
    'leaves explicit server responses outside the typed frame budget',
    () async {
      var encodes = 0;
      final server = _server<ServerResponse>(
        maxResponseBytes: Server.minimumFunctionResponseFrameBytes,
        handler: (_) => ServerResponse.bytes(List<int>.filled(64, 1)),
        encodeOutput: (_) {
          encodes++;
          return null;
        },
      );

      final response = await server.handle(_request());
      expect(response.status, 200);
      expect(await response.readBytes(), hasLength(64));
      expect(encodes, 0);
    },
  );
}

Server _server<O>({
  required int maxResponseBytes,
  required ServerFunctionHandler<NoServerInput, O> handler,
  Serializer? serializer,
  ValueEncoder<Object?>? encodeOutput,
  bool exposeErrors = false,
}) => Server(
  routes: const [],
  functions: <String, ServerFunctionBinding>{
    'test': ServerFunctionBinding(
      ServerFunction<NoServerInput, O>(handler: handler),
      encodeOutput: encodeOutput,
    ),
  },
  serializer: serializer,
  maxFunctionResponseFrameBytes: maxResponseBytes,
  exposeErrors: exposeErrors,
  allowRpcWithoutOrigin: true,
  onError: (_, _, _) {},
);

typedef _Post = ({int id, String title});

ServerRequest _request([String path = '/__odroe/functions/test']) =>
    ServerRequest.bytes(
      method: HttpMethod.post,
      uri: Uri.parse('http://localhost$path'),
      headers: Headers.single(<String, String>{
        'content-type': 'application/json; charset=utf-8',
        'x-odroe-server-function': 'true',
      }),
      body: utf8.encode('{"data":null}'),
    );

final class _AdaptedValue {
  const _AdaptedValue();
}

final class _CountingAdapter implements SerializationAdapter<_AdaptedValue> {
  var encodes = 0;

  @override
  String get tag => 'AdaptedValue';

  @override
  bool canEncode(Object value) => value is _AdaptedValue;

  @override
  Object? encode(_AdaptedValue value, Serializer serializer) {
    encodes++;
    return 'x' * 1024;
  }

  @override
  _AdaptedValue decode(Object? value, Serializer serializer) =>
      const _AdaptedValue();
}
