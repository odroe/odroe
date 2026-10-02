import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:odroe/odroe.dart';
import 'package:odroe/rpc.dart';
import 'package:test/test.dart';

void main() {
  test('requires a positive buffered request body budget', () {
    var defaultClientCreations = 0;
    for (final maxBytes in <int>[0, -1]) {
      http.runWithClient(
        () {
          expect(
            () => HttpTransport(maxRequestBodyBytes: maxBytes),
            throwsA(
              isA<ArgumentError>().having(
                (error) => error.invalidValue,
                'invalidValue',
                maxBytes,
              ),
            ),
          );
        },
        () {
          defaultClientCreations++;
          return _RecordingHttpClient();
        },
      );
    }
    expect(defaultClientCreations, 0);

    final transport = HttpTransport(client: _RecordingHttpClient());
    expect(
      transport.maxRequestBodyBytes,
      HttpTransport.defaultMaxRequestBodyBytes,
    );
    expect(HttpTransport.defaultMaxRequestBodyBytes, 10 * 1024 * 1024);
    expect(
      const PayloadTooLargeException(4).toString(),
      'Request payload exceeds 4 bytes.',
    );
  });

  test('accepts a request body at the exact byte budget', () async {
    const maxBytes = 4;
    final httpClient = _RecordingHttpClient();
    final transport = HttpTransport(
      client: httpClient,
      maxRequestBodyBytes: maxBytes,
    );

    await transport.send(
      ServerRequest.bytes(
        method: HttpMethod.post,
        uri: Uri.parse('https://api.example.com/function'),
        body: const <int>[1, 2, 3, 4],
      ),
    );

    final outgoing = httpClient.request! as http.AbortableRequest;
    expect(outgoing.bodyBytes, const <int>[1, 2, 3, 4]);
    expect(outgoing.contentLength, maxBytes);
  });

  test('validates the module response frame budget before setup', () {
    expect(() => RpcModule.http(maxResponseFrameBytes: 0), throwsArgumentError);
  });

  test('rejects an invalid HTTP base URI before creating a transport', () {
    var defaultClientCreations = 0;
    http.runWithClient(
      () {
        expect(
          () => RpcModule.http(),
          throwsA(
            isA<ArgumentError>()
                .having((error) => error.invalidValue, 'invalidValue', Uri.base)
                .having(
                  (error) => error.message,
                  'message',
                  contains('Omit only for same-origin Web RPC.'),
                ),
          ),
        );
        for (final value in <Uri>[
          Uri.parse('/api'),
          Uri.parse('http:///rpc'),
          Uri.parse('ftp://api.example.com'),
          Uri.parse('https://user@api.example.com'),
        ]) {
          expect(
            () => RpcModule.http(baseUri: value),
            throwsA(
              isA<ArgumentError>()
                  .having((error) => error.invalidValue, 'invalidValue', value)
                  .having(
                    (error) => error.message,
                    'message',
                    contains('Omit only for same-origin Web RPC.'),
                  ),
            ),
            reason: value.toString(),
          );
        }
      },
      () {
        defaultClientCreations++;
        return _RecordingHttpClient();
      },
    );
    expect(defaultClientCreations, 0);
  });

  test('accepts explicit HTTP and HTTPS module base URIs', () {
    final transport = HttpTransport(client: _RecordingHttpClient());
    addTearDown(transport.close);

    for (final value in <Uri>[
      Uri.parse('http://localhost:8080'),
      Uri.parse('https://api.example.com/app?tenant=one#section'),
    ]) {
      final module = RpcModule.http(baseUri: value, transport: transport);
      expect(module.client.baseUri, value);
    }
  });

  test('configures only the module-owned HTTP request body budget', () {
    final module = RpcModule.http(
      baseUri: Uri.parse('https://api.example.com'),
      maxRequestBodyBytes: 512,
    );
    final transport = module.client.transport as HttpTransport;
    addTearDown(transport.close);
    expect(transport.maxRequestBodyBytes, 512);

    expect(
      () => RpcModule.http(
        baseUri: Uri.parse('https://api.example.com'),
        maxRequestBodyBytes: 0,
      ),
      throwsArgumentError,
    );
    final callerOwned = HttpTransport(client: _RecordingHttpClient());
    expect(
      () => RpcModule.http(transport: callerOwned, maxRequestBodyBytes: 512),
      throwsArgumentError,
    );
  });

  test('default HTTP transport resolves bearer headers per request', () async {
    final authorizations = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      authorizations.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'version': 1,
          'type': 'data',
          'data': authorizations.length,
        }),
      );
      await request.response.close();
    });

    var token = 'first';
    var providerCalls = 0;
    final context = await AppContext.create(<Module>[
      RpcModule.http(
        baseUri: Uri(
          scheme: 'http',
          host: server.address.address,
          port: server.port,
        ),
        maxResponseFrameBytes: 512,
        headersProvider: () async {
          providerCalls++;
          await Future<void>.delayed(Duration.zero);
          return Headers.single(<String, String>{
            'authorization': 'Bearer $token',
          });
        },
      ),
    ]);
    addTearDown(context.dispose);
    final client = context.read(rpcClientKey);
    expect(client.maxResponseFrameBytes, 512);
    const function = ServerFunctionRef<NoServerInput, int>(id: 'session.read');

    expect(await function(client, const NoServerInput()), 1);
    token = 'second';
    expect(await function(client, const NoServerInput()), 2);

    expect(providerCalls, 2);
    expect(authorizations, <String?>['Bearer first', 'Bearer second']);
  });

  test('builds an abortable package:http request', () async {
    final cancelled = Completer<void>();
    final httpClient = _RecordingHttpClient();
    final transport = HttpTransport(client: httpClient);

    final response = await transport.send(
      ServerRequest.bytes(
        method: HttpMethod.post,
        uri: Uri.parse('https://api.example.com/function'),
        body: utf8.encode('{}'),
        cancelled: cancelled.future,
      ),
    );

    expect(await response.readText(), 'ok');
    expect(httpClient.request, isA<http.AbortableRequest>());
    final request = httpClient.request! as http.AbortableRequest;
    expect(request.abortTrigger, isNotNull);

    cancelled.complete();
    await expectLater(request.abortTrigger, completes);
  });

  test('cancels while buffering a streaming request body', () async {
    final bodyStarted = Completer<void>();
    final bodyCancelled = Completer<void>();
    final body = StreamController<List<int>>(
      onListen: bodyStarted.complete,
      onCancel: () {
        bodyCancelled.complete();
        return Future<void>.error(StateError('cleanup failed'));
      },
    );
    addTearDown(body.close);
    final cancelled = Completer<void>();
    final httpClient = _RecordingHttpClient();
    final transport = HttpTransport(client: httpClient);

    final send = transport.send(
      ServerRequest(
        method: HttpMethod.post,
        uri: Uri.parse('https://api.example.com/function'),
        body: body.stream,
        cancelled: cancelled.future,
      ),
    );
    await bodyStarted.future;
    cancelled.complete();

    await expectLater(send, throwsA(isA<RpcCancelledException>()));
    await expectLater(bodyCancelled.future, completes);
    expect(httpClient.request, isNull);
  });

  test('preserves request size errors when body cleanup fails', () async {
    const maxBytes = 4;
    final bodyCancelled = Completer<void>();
    late final StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onListen: () {
        body
          ..add(Uint8List(maxBytes))
          ..add(const <int>[0]);
      },
      onCancel: () {
        bodyCancelled.complete();
        return Future<void>.error(StateError('cleanup failed'));
      },
    );
    addTearDown(body.close);
    final httpClient = _RecordingHttpClient();
    final transport = HttpTransport(
      client: httpClient,
      maxRequestBodyBytes: maxBytes,
    );

    await expectLater(
      transport.send(
        ServerRequest(
          method: HttpMethod.post,
          uri: Uri.parse('https://api.example.com/function'),
          body: body.stream,
        ),
      ),
      throwsA(
        isA<PayloadTooLargeException>().having(
          (error) => error.maxBytes,
          'maxBytes',
          maxBytes,
        ),
      ),
    );
    await expectLater(bodyCancelled.future, completes);
    expect(httpClient.request, isNull);
  });

  test('derives HTTP framing from the buffered body', () async {
    const maxBytes = 8;
    final httpClient = _RecordingHttpClient();
    final transport = HttpTransport(
      client: httpClient,
      maxRequestBodyBytes: maxBytes,
    );

    final response = await transport.send(
      ServerRequest(
        method: HttpMethod.post,
        uri: Uri.parse('https://api.example.com/function'),
        headers: Headers.single(<String, String>{
          'content-length': '1',
          'transfer-encoding': 'chunked',
        }),
        body: Stream<List<int>>.fromIterable(const <List<int>>[
          <int>[1, 2, 3],
          <int>[4, 5],
        ]),
      ),
    );

    expect(await response.readText(), 'ok');
    final outgoing = httpClient.request! as http.AbortableRequest;
    expect(outgoing.bodyBytes, const <int>[1, 2, 3, 4, 5]);
    expect(outgoing.contentLength, 5);
    expect(outgoing.headers, isNot(contains('content-length')));
    expect(outgoing.headers, isNot(contains('transfer-encoding')));
  });

  test('preserves unrelated package:http abort errors', () async {
    final transport = HttpTransport(client: _AbortingHttpClient());

    await expectLater(
      transport.send(
        ServerRequest.bytes(
          method: HttpMethod.get,
          uri: Uri.parse('https://api.example.com/function'),
        ),
      ),
      throwsA(isA<http.RequestAbortedException>()),
    );
  });

  test('cancels a request before response headers arrive', () async {
    final received = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      if (!received.isCompleted) received.complete();
      unawaited(request.drain<void>());
    });
    final transport = HttpTransport();
    addTearDown(transport.close);
    final client = RpcClient(baseUri: _baseUri(server), transport: transport);
    final cancelled = Completer<void>();

    final call = const ServerFunctionRef<int, int>(id: 'wait')(
      client,
      1,
      cancelled: cancelled.future,
    );
    await received.future.timeout(const Duration(seconds: 5));
    cancelled.complete();

    await expectLater(
      call.timeout(const Duration(seconds: 5)),
      throwsA(isA<RpcCancelledException>()),
    );
  });

  test('cancels while reading a value response body', () async {
    final bodyStarted = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      try {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"version":1,"type":"data","data":');
        await request.response.flush();
        if (!bodyStarted.isCompleted) bodyStarted.complete();
        await release.future;
        request.response.write('1}');
        await request.response.close();
      } on Object {
        // The client intentionally aborts this response.
      }
    });
    final transport = HttpTransport();
    addTearDown(transport.close);
    final client = RpcClient(baseUri: _baseUri(server), transport: transport);
    final cancelled = Completer<void>();

    final call = const ServerFunctionRef<int, int>(id: 'read')(
      client,
      1,
      cancelled: cancelled.future,
    );
    await bodyStarted.future.timeout(const Duration(seconds: 5));
    cancelled.complete();

    await expectLater(
      call.timeout(const Duration(seconds: 5)),
      throwsA(isA<RpcCancelledException>()),
    );
    release.complete();
  });

  test('uses decoded response bytes instead of compressed length', () async {
    final frame = utf8.encode(
      jsonEncode(<String, Object?>{'version': 1, 'type': 'data', 'data': 1}),
    );
    final compressed = gzip.encode(frame);
    expect(compressed.length, greaterThan(frame.length));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.contentEncodingHeader, 'gzip');
      request.response
        ..contentLength = compressed.length
        ..add(compressed);
      await request.response.close();
    });
    final transport = HttpTransport();
    addTearDown(transport.close);
    final client = RpcClient(
      baseUri: _baseUri(server),
      transport: transport,
      maxResponseFrameBytes: frame.length,
    );

    expect(await const ServerFunctionRef<int, int>(id: 'read')(client, 1), 1);
  });

  test('cancels a stream after its first frame', () async {
    final bodyStarted = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      try {
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'application',
          'x-ndjson',
          charset: 'utf-8',
        );
        request.response.bufferOutput = false;
        request.response.write('{"version":1,"type":"data","data":1}\n');
        await request.response.flush();
        if (!bodyStarted.isCompleted) bodyStarted.complete();
        await release.future;
        request.response.write('{"version":1,"type":"data","data":2}\n');
        await request.response.close();
      } on Object {
        // The client intentionally aborts this response.
      }
    });
    final transport = HttpTransport();
    addTearDown(transport.close);
    final client = RpcClient(baseUri: _baseUri(server), transport: transport);
    final cancelled = Completer<void>();
    final stream = await const ServerStreamFunctionRef<int, int>(id: 'watch')(
      client,
      1,
      cancelled: cancelled.future,
    );
    final firstValue = Completer<int>();
    final streamError = Completer<Object>();
    final subscription = stream.listen(
      (value) {
        if (!firstValue.isCompleted) firstValue.complete(value);
      },
      onError: (Object error) {
        if (!streamError.isCompleted) streamError.complete(error);
      },
    );
    addTearDown(subscription.cancel);

    await bodyStarted.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('Server body did not start.'),
    );
    expect(
      await firstValue.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            throw TimeoutException('The first stream value did not arrive.'),
      ),
      1,
    );
    cancelled.complete();

    expect(
      await streamError.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            throw TimeoutException('The cancellation error did not arrive.'),
      ),
      isA<RpcCancelledException>(),
    );
    release.complete();
  });
}

Uri _baseUri(HttpServer server) =>
    Uri(scheme: 'http', host: server.address.address, port: server.port);

final class _RecordingHttpClient extends http.BaseClient {
  http.BaseRequest? request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    await request.finalize().drain<void>();
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('ok')),
      200,
    );
  }
}

final class _AbortingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future<http.StreamedResponse>.error(http.RequestAbortedException());
}
