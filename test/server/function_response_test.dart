import 'dart:convert';
import 'dart:typed_data';

import 'package:odroe/rpc.dart';
import 'package:odroe/server.dart';
import 'package:test/test.dart';

void main() {
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
    expect(await oversizedResponse.readText(), '{"type":"error"}');

    final exposedFailure = _server<String>(
      maxResponseBytes: Server.minimumFunctionResponseFrameBytes,
      exposeErrors: true,
      handler: (_) => throw StateError('x' * 1024),
    );
    final failureResponse = await exposedFailure.handle(_request());
    expect(failureResponse.status, 500);
    expect(await failureResponse.readText(), '{"type":"error"}');
  });

  test('bounds an oversized RPC redirect inside its catch path', () async {
    final server = _server<Never>(
      maxResponseBytes: Server.minimumFunctionResponseFrameBytes,
      handler: (_) =>
          throw Redirect(Uri.parse('https://example.com/${'x' * 1024}')),
    );

    final response = await server.handle(_request());
    expect(response.status, 500);
    expect(await response.readText(), '{"type":"error"}');
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
      final server = _server<ServerResponse>(
        maxResponseBytes: Server.minimumFunctionResponseFrameBytes,
        handler: (_) => ServerResponse.bytes(List<int>.filled(64, 1)),
      );

      final response = await server.handle(_request());
      expect(response.status, 200);
      expect(await response.readBytes(), hasLength(64));
    },
  );
}

Server _server<O>({
  required int maxResponseBytes,
  required ServerFunctionHandler<NoServerInput, O> handler,
  Serializer? serializer,
  bool exposeErrors = false,
}) => Server(
  routes: const [],
  functions: <String, ServerFunctionBinding>{
    'test': ServerFunctionBinding(
      ServerFunction<NoServerInput, O>(handler: handler),
    ),
  },
  serializer: serializer,
  maxFunctionResponseFrameBytes: maxResponseBytes,
  exposeErrors: exposeErrors,
  allowRpcWithoutOrigin: true,
);

ServerRequest _request() => ServerRequest.bytes(
  method: HttpMethod.post,
  uri: Uri.parse('http://localhost/__odroe/functions/test'),
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
