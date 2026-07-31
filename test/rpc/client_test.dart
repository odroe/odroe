import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:odroe/rpc.dart';
import 'package:odroe/server.dart';
import 'package:test/test.dart';

void main() {
  test('resolves fresh application headers once per RPC request', () async {
    final applicationHeaders = Headers.single(<String, String>{
      'accept': 'text/plain',
      'authorization': 'Bearer initial',
      'origin': 'https://invalid.example',
      'x-odroe-server-function': 'false',
    });
    final transport = _RecordingTransport(<ServerResponse>[
      _dataResponse('get'),
      _dataResponse('post'),
      _streamResponse('stream'),
    ]);
    var token = 'first';
    var providerCalls = 0;
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com/v1/'),
      transport: transport,
      headersProvider: () async {
        providerCalls++;
        applicationHeaders.set('authorization', 'Bearer $token');
        return applicationHeaders;
      },
    );

    final getValue = await const ServerFunctionRef<NoServerInput, String>(
      id: 'read',
      method: HttpMethod.get,
    )(client, const NoServerInput());
    token = 'second';
    final postValue = await const ServerFunctionRef<int, String>(id: 'write')(
      client,
      42,
    );
    token = 'third';
    final stream = await const ServerStreamFunctionRef<NoServerInput, String>(
      id: 'watch',
    )(client, const NoServerInput());

    expect(getValue, 'get');
    expect(postValue, 'post');
    expect(await stream.toList(), <String>['stream']);
    expect(providerCalls, 3);
    expect(
      transport.requests.map(
        (request) => request.headers.value('authorization'),
      ),
      <String?>['Bearer first', 'Bearer second', 'Bearer third'],
    );
    for (final request in transport.requests) {
      expect(
        request.headers.value('accept'),
        'application/json, application/x-ndjson',
      );
      expect(request.headers.value('origin'), 'https://api.example.com');
      expect(request.headers.value('x-odroe-server-function'), 'true');
    }
    expect(transport.requests[0].method, HttpMethod.get);
    expect(transport.requests[0].uri.path, '/__odroe/functions/read');
    expect(transport.requests[0].uri.queryParameters, contains('payload'));
    expect(transport.requests[1].method, HttpMethod.post);
    expect(
      transport.requests[1].headers.value('content-type'),
      'application/json; charset=utf-8',
    );
    expect(jsonDecode(transport.requests[1].body), <String, Object?>{
      'data': 42,
    });
    expect(transport.requests[2].method, HttpMethod.post);

    expect(applicationHeaders.value('accept'), 'text/plain');
    expect(applicationHeaders.value('origin'), 'https://invalid.example');
    expect(applicationHeaders.value('x-odroe-server-function'), 'false');
  });

  test('does not send when the headers provider fails', () async {
    final error = StateError('Token refresh failed.');
    final transport = _RecordingTransport(<ServerResponse>[
      _dataResponse(null),
    ]);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: transport,
      headersProvider: () async => throw error,
    );

    await expectLater(
      const ServerFunctionRef<NoServerInput, Object?>(id: 'read')(
        client,
        const NoServerInput(),
      ),
      throwsA(same(error)),
    );
    expect(transport.requests, isEmpty);
  });

  test('passes bearer headers through function middleware', () async {
    Future<ServerResponse> requireSession(RequestContext context, Next next) {
      if (context.request.headers.value('authorization') != 'Bearer fresh') {
        throw const HttpError(401, 'Sign in required.');
      }
      return next();
    }

    final server = Server(
      routes: const [],
      functions: <String, ServerFunctionBinding>{
        'session.read': ServerFunctionBinding(
          ServerFunction<NoServerInput, String>(
            middleware: <Middleware>[requireSession],
            handler: (context) =>
                context.request.request.headers.value('authorization')!,
          ),
        ),
      },
    );
    var token = 'stale';
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _ServerTransport(server),
      headersProvider: () =>
          Headers.single(<String, String>{'authorization': 'Bearer $token'}),
    );
    const function = ServerFunctionRef<NoServerInput, String>(
      id: 'session.read',
    );

    await expectLater(
      function(client, const NoServerInput()),
      throwsA(
        isA<RemoteServerException>()
            .having((error) => error.status, 'status', 401)
            .having((error) => error.message, 'message', 'Sign in required.'),
      ),
    );
    token = 'fresh';
    expect(await function(client, const NoServerInput()), 'Bearer fresh');
  });

  test(
    'classifies non-protocol HTTP responses without leaking format errors',
    () async {
      final transport = _RecordingTransport(<ServerResponse>[
        ServerResponse.text('Unauthorized', status: 401),
        ServerResponse.html('<h1>Forbidden</h1>', status: 403),
        ServerResponse.html('<h1>Proxy response</h1>'),
        ServerResponse.json(<String, Object?>{
          'version': 1,
          'type': 'unexpected',
        }),
      ]);
      final client = RpcClient(
        baseUri: Uri.parse('https://api.example.com'),
        transport: transport,
      );
      const function = ServerFunctionRef<NoServerInput, Object?>(id: 'read');

      await expectLater(
        function(client, const NoServerInput()),
        throwsA(
          isA<RemoteServerException>().having(
            (error) => error.status,
            'status',
            401,
          ),
        ),
      );
      await expectLater(
        function(client, const NoServerInput()),
        throwsA(
          isA<RemoteServerException>().having(
            (error) => error.status,
            'status',
            403,
          ),
        ),
      );
      await expectLater(
        function(client, const NoServerInput()),
        throwsA(isA<RpcProtocolException>()),
      );
      await expectLater(
        function(client, const NoServerInput()),
        throwsA(isA<RpcProtocolException>()),
      );
      expect(transport.requests, hasLength(4));
    },
  );

  test('rejects non-success data and streaming responses', () async {
    final transport = _RecordingTransport(<ServerResponse>[
      _dataResponse('ignored', status: 401),
      _streamResponse('ignored', status: 401),
      ServerResponse(
        status: 401,
        headers: Headers.single(<String, String>{
          'content-type': 'application/x-ndjson; charset=utf-8',
        }),
      ),
    ]);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: transport,
    );
    const valueFunction = ServerFunctionRef<NoServerInput, Object?>(id: 'read');
    const streamFunction = ServerStreamFunctionRef<NoServerInput, Object?>(
      id: 'watch',
    );

    for (var index = 0; index < 2; index++) {
      await expectLater(
        valueFunction(client, const NoServerInput()),
        throwsA(
          isA<RemoteServerException>().having(
            (error) => error.status,
            'status',
            401,
          ),
        ),
      );
    }
    await expectLater(
      streamFunction(client, const NoServerInput()),
      throwsA(
        isA<RemoteServerException>().having(
          (error) => error.status,
          'status',
          401,
        ),
      ),
    );
    expect(transport.requests, hasLength(3));
  });

  test('validates known frame fields and invalid UTF-8', () async {
    final transport = _RecordingTransport(<ServerResponse>[
      ServerResponse.json(<String, Object?>{
        'version': 1,
        'type': 'error',
        'message': 42,
      }),
      ServerResponse.json(<String, Object?>{
        'version': 1,
        'type': 'redirect',
        'location': 42,
        'status': '302',
      }),
      ServerResponse.json(<String, Object?>{
        'version': 1,
        'type': 'error',
        'message': 42,
      }, status: 401),
      ServerResponse.bytes(<int>[
        0xff,
      ], contentType: 'application/json; charset=utf-8'),
      ServerResponse.bytes(
        <int>[0xff],
        status: 401,
        contentType: 'application/json; charset=utf-8',
      ),
    ]);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: transport,
    );
    const function = ServerFunctionRef<NoServerInput, Object?>(id: 'read');

    for (var index = 0; index < 2; index++) {
      await expectLater(
        function(client, const NoServerInput()),
        throwsA(isA<RpcProtocolException>()),
      );
    }
    await expectLater(
      function(client, const NoServerInput()),
      throwsA(
        isA<RemoteServerException>().having(
          (error) => error.status,
          'status',
          401,
        ),
      ),
    );
    await expectLater(
      function(client, const NoServerInput()),
      throwsA(isA<RpcProtocolException>()),
    );
    await expectLater(
      function(client, const NoServerInput()),
      throwsA(
        isA<RemoteServerException>().having(
          (error) => error.status,
          'status',
          401,
        ),
      ),
    );
  });

  test('cancels a stream body rejected by a value function', () async {
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: cancelled.complete,
    );
    addTearDown(controller.close);
    final transport = _RecordingTransport(<ServerResponse>[
      ServerResponse(
        headers: Headers.single(<String, String>{
          'content-type': 'application/x-ndjson; charset=utf-8',
        }),
        body: controller.stream,
      ),
    ]);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: transport,
    );

    await expectLater(
      const ServerFunctionRef<NoServerInput, Object?>(id: 'read')(
        client,
        const NoServerInput(),
      ),
      throwsA(isA<RpcProtocolException>()),
    );
    await expectLater(cancelled.future, completes);
  });

  test('classifies invalid stream UTF-8 as a protocol error', () async {
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse.bytes(<int>[
          0xff,
        ], contentType: 'application/x-ndjson; charset=utf-8'),
      ]),
    );

    final stream = await const ServerStreamFunctionRef<NoServerInput, Object?>(
      id: 'watch',
    )(client, const NoServerInput());

    await expectLater(stream.toList(), throwsA(isA<RpcProtocolException>()));
  });

  test('leaves raw server responses to the caller', () async {
    final response = ServerResponse.text('Unauthorized', status: 401);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[response]),
    );

    final result = await const ServerFunctionRef<NoServerInput, ServerResponse>(
      id: 'raw',
    )(client, const NoServerInput());

    expect(result, same(response));
    expect(result.status, 401);
  });
}

ServerResponse _dataResponse(Object? data, {int status = 200}) =>
    ServerResponse.json(<String, Object?>{
      'version': 1,
      'type': 'data',
      'data': data,
    }, status: status);

ServerResponse _streamResponse(
  Object? data, {
  int status = 200,
}) => ServerResponse(
  status: status,
  headers: Headers.single(<String, String>{
    'content-type': 'application/x-ndjson; charset=utf-8',
  }),
  body: Stream<List<int>>.value(
    utf8.encode(
      '${jsonEncode(<String, Object?>{'version': 1, 'type': 'data', 'data': data})}\n',
    ),
  ),
);

final class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final HttpMethod method;
  final Uri uri;
  final Headers headers;
  final String body;
}

final class _RecordingTransport implements RpcTransport {
  _RecordingTransport(Iterable<ServerResponse> responses)
    : _responses = Queue<ServerResponse>.of(responses);

  final Queue<ServerResponse> _responses;
  final List<_RecordedRequest> requests = <_RecordedRequest>[];

  @override
  Future<ServerResponse> send(ServerRequest request) async {
    requests.add(
      _RecordedRequest(
        method: request.method,
        uri: request.uri,
        headers: request.headers.copy(),
        body: await request.readText(),
      ),
    );
    return _responses.removeFirst();
  }
}

final class _ServerTransport implements RpcTransport {
  const _ServerTransport(this.server);

  final Server server;

  @override
  Future<ServerResponse> send(ServerRequest request) => server.handle(request);
}
