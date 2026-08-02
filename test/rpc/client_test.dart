import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:odroe/rpc.dart';
import 'package:odroe/server.dart';
import 'package:test/test.dart';

void main() {
  test('requires a positive typed response frame budget', () {
    expect(
      () => RpcClient(
        baseUri: Uri.parse('https://api.example.com'),
        transport: _RecordingTransport(const <ServerResponse>[]),
        maxResponseFrameBytes: 0,
      ),
      throwsArgumentError,
    );
    expect(
      RpcClient(
        baseUri: Uri.parse('https://api.example.com'),
        transport: _RecordingTransport(const <ServerResponse>[]),
      ).maxResponseFrameBytes,
      RpcClient.defaultMaxResponseFrameBytes,
    );
    expect(RpcClient.defaultMaxResponseFrameBytes, 1024 * 1024);

    expect(
      RpcClient(
        baseUri: Uri.parse('https://api.example.com'),
        transport: _RecordingTransport(const <ServerResponse>[]),
        functionPath: '/rpc/',
      ).functionPath,
      '/rpc',
    );
    for (final path in <String>['', '/', 'rpc']) {
      expect(
        () => RpcClient(
          baseUri: Uri.parse('https://api.example.com'),
          transport: _RecordingTransport(const <ServerResponse>[]),
          functionPath: path,
        ),
        throwsArgumentError,
        reason: path,
      );
    }
  });

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

  test('encodes value and stream inputs before serialization', () async {
    final transport = _RecordingTransport(<ServerResponse>[
      _dataResponse('saved'),
      _streamResponse('watching'),
    ]);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: transport,
    );
    var encodes = 0;
    Object? encodePost(_Post post) {
      encodes++;
      return <String, Object?>{'id': post.id, 'title': post.title};
    }

    final saved = await ServerFunctionRef<_Post, String>(
      id: 'save',
      encodeInput: encodePost,
    )(client, (id: 42, title: 'Odroe'));
    final stream = await ServerStreamFunctionRef<_Post, String>(
      id: 'watch',
      encodeInput: encodePost,
    )(client, (id: 43, title: 'Edge'));

    expect(saved, 'saved');
    expect(await stream.toList(), <String>['watching']);
    expect(encodes, 2);
    expect(jsonDecode(transport.requests[0].body), <String, Object?>{
      'data': <String, Object?>{'id': 42, 'title': 'Odroe'},
    });
    expect(jsonDecode(transport.requests[1].body), <String, Object?>{
      'data': <String, Object?>{'id': 43, 'title': 'Edge'},
    });
  });

  test(
    'honors null input encodings and does not send encoder failures',
    () async {
      final failure = ArgumentError('Invalid post.');
      final transport = _RecordingTransport(<ServerResponse>[
        _dataResponse(null),
      ]);
      var headerCalls = 0;
      final client = RpcClient(
        baseUri: Uri.parse('https://api.example.com'),
        transport: transport,
        headersProvider: () {
          headerCalls++;
          return Headers();
        },
      );

      await ServerFunctionRef<_Post, Object?>(
        id: 'clear',
        encodeInput: (_) => null,
      )(client, (id: 42, title: 'Odroe'));
      await expectLater(
        ServerFunctionRef<_Post, Object?>(
          id: 'save',
          encodeInput: (_) => throw failure,
        )(client, (id: 43, title: 'Invalid')),
        throwsA(same(failure)),
      );

      expect(jsonDecode(transport.requests.single.body), <String, Object?>{
        'data': null,
      });
      expect(headerCalls, 1);
    },
  );

  test('forwards cancellation to value and stream requests', () async {
    final getCancelled = Completer<void>();
    final postCancelled = Completer<void>();
    final streamCancelled = Completer<void>();
    final transport = _RecordingTransport(<ServerResponse>[
      _dataResponse('get'),
      _dataResponse('post'),
      _streamResponse('stream'),
    ]);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: transport,
    );

    await const ServerFunctionRef<NoServerInput, String>(
      id: 'read',
      method: HttpMethod.get,
    )(client, const NoServerInput(), cancelled: getCancelled.future);
    await const ServerFunctionRef<int, String>(id: 'write')(
      client,
      42,
      cancelled: postCancelled.future,
    );
    final stream = await const ServerStreamFunctionRef<NoServerInput, String>(
      id: 'watch',
    )(client, const NoServerInput(), cancelled: streamCancelled.future);
    await stream.drain<void>();

    expect(transport.requests[0].cancelled, same(getCancelled.future));
    expect(transport.requests[1].cancelled, same(postCancelled.future));
    expect(transport.requests[2].cancelled, same(streamCancelled.future));
  });

  test('cancels while resolving application headers', () async {
    final providerStarted = Completer<void>();
    final providerRelease = Completer<Headers>();
    final cancelled = Completer<void>();
    final transport = _RecordingTransport(<ServerResponse>[
      _dataResponse(null),
    ]);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: transport,
      headersProvider: () {
        providerStarted.complete();
        return providerRelease.future;
      },
    );

    final call = const ServerFunctionRef<NoServerInput, Object?>(id: 'read')(
      client,
      const NoServerInput(),
      cancelled: cancelled.future,
    );
    await providerStarted.future;
    cancelled.complete();

    await expectLater(call, throwsA(isA<RpcCancelledException>()));
    expect(transport.requests, isEmpty);

    providerRelease.complete(Headers());
    await Future<void>.delayed(Duration.zero);
    expect(transport.requests, isEmpty);
  });

  test('pre-cancelled calls do not start providers or transports', () async {
    final cancelled = Completer<void>()..complete();
    var providerCalls = 0;
    final transport = _RecordingTransport(<ServerResponse>[
      _dataResponse(null),
    ]);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: transport,
      headersProvider: () {
        providerCalls++;
        return Headers();
      },
    );

    await expectLater(
      const ServerFunctionRef<Object, Object?>(id: 'read')(
        client,
        Object(),
        cancelled: cancelled.future,
      ),
      throwsA(isA<RpcCancelledException>()),
    );

    expect(providerCalls, 0);
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

  test('classifies invalid typed output as a protocol error', () async {
    final transport = _RecordingTransport(<ServerResponse>[
      _dataResponse('not an integer'),
      ServerResponse.json(<String, Object?>{
        'version': 1,
        'type': 'data',
        'data': <String, Object?>{r'$type': 'Unknown', r'$value': 1},
      }),
      _streamResponse('not an integer'),
    ]);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: transport,
    );
    const value = ServerFunctionRef<NoServerInput, int>(id: 'read');

    for (var index = 0; index < 2; index++) {
      await expectLater(
        value(client, const NoServerInput()),
        throwsA(isA<RpcProtocolException>()),
      );
    }
    final stream = await const ServerStreamFunctionRef<NoServerInput, int>(
      id: 'watch',
    )(client, const NoServerInput());
    await expectLater(stream.toList(), throwsA(isA<RpcProtocolException>()));
  });

  test('rejects empty successful typed responses', () async {
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse(),
        ServerResponse(status: 204),
      ]),
    );
    const function = ServerFunctionRef<NoServerInput, Object?>(id: 'read');

    for (var index = 0; index < 2; index++) {
      await expectLater(
        function(client, const NoServerInput()),
        throwsA(isA<RpcProtocolException>()),
      );
    }
  });

  test('validates frame versions and control response statuses', () async {
    final transport = _RecordingTransport(<ServerResponse>[
      ServerResponse.json(<String, Object?>{'type': 'data', 'data': 1}),
      ServerResponse.json(<String, Object?>{
        'version': 2,
        'type': 'data',
        'data': 1,
      }),
      ServerResponse.json(<String, Object?>{
        'version': 1,
        'type': 'notFound',
        'message': 'missing',
      }),
      ServerResponse.json(<String, Object?>{
        'version': 1,
        'type': 'notFound',
        'message': 'missing',
      }, status: 404),
      ServerResponse.json(<String, Object?>{
        'version': 1,
        'type': 'redirect',
        'location': '/next',
        'status': 302,
      }),
      ServerResponse.json(<String, Object?>{
        'version': 1,
        'type': 'redirect',
        'location': '/next',
        'status': 307,
      }, status: 302),
      ServerResponse.json(<String, Object?>{
        'version': 1,
        'type': 'redirect',
        'location': '/next',
        'status': 307,
      }, status: 307),
    ]);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: transport,
    );
    const function = ServerFunctionRef<NoServerInput, Object?>(id: 'read');

    for (var index = 0; index < 3; index++) {
      await expectLater(
        function(client, const NoServerInput()),
        throwsA(isA<RpcProtocolException>()),
      );
    }
    await expectLater(
      function(client, const NoServerInput()),
      throwsA(
        isA<NotFound>().having((error) => error.message, 'message', 'missing'),
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
          302,
        ),
      ),
    );
    await expectLater(
      function(client, const NoServerInput()),
      throwsA(
        isA<Redirect>()
            .having((error) => error.location.path, 'location', '/next')
            .having((error) => error.status, 'status', 307),
      ),
    );
    expect(transport.requests, hasLength(7));
  });

  test('round trips redirects from Server through RpcClient', () async {
    final server = Server(
      routes: const [],
      functions: <String, ServerFunctionBinding>{
        'move': ServerFunctionBinding(
          ServerFunction<NoServerInput, Never>(
            handler: (_) => throw Redirect(Uri.parse('/next'), status: 307),
          ),
        ),
      },
    );
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _ServerTransport(server),
    );

    await expectLater(
      const ServerFunctionRef<NoServerInput, Never>(id: 'move')(
        client,
        const NoServerInput(),
      ),
      throwsA(
        isA<Redirect>()
            .having((error) => error.location.path, 'location', '/next')
            .having((error) => error.status, 'status', 307),
      ),
    );
  });

  test('accepts a typed value frame exactly at its byte budget', () async {
    final frame = _encodedDataFrame('café');
    final exactClient = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse.bytes(
          frame,
          contentType: 'application/json; charset=utf-8',
        ),
      ]),
      maxResponseFrameBytes: frame.length,
    );

    expect(
      await const ServerFunctionRef<NoServerInput, String>(id: 'read')(
        exactClient,
        const NoServerInput(),
      ),
      'café',
    );

    final undersizedClient = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse.bytes(
          frame,
          contentType: 'application/json; charset=utf-8',
        ),
      ]),
      maxResponseFrameBytes: frame.length - 1,
    );
    await expectLater(
      const ServerFunctionRef<NoServerInput, String>(id: 'read')(
        undersizedClient,
        const NoServerInput(),
      ),
      throwsA(isA<RpcProtocolException>()),
    );
  });

  test('rejects and cancels an oversized typed value frame', () async {
    final bodyCancelled = Completer<void>();
    late final StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onListen: () {
        body
          ..add(List<int>.filled(32, 0x20))
          ..add(List<int>.filled(33, 0x20));
      },
      onCancel: () {
        bodyCancelled.complete();
        return Future<void>.error(StateError('cleanup failed'));
      },
    );
    addTearDown(body.close);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse(
          headers: Headers.single(<String, String>{
            'content-length': '1',
            'content-type': 'application/json; charset=utf-8',
          }),
          body: body.stream,
        ),
      ]),
      maxResponseFrameBytes: 64,
    );

    await expectLater(
      const ServerFunctionRef<NoServerInput, Object?>(id: 'read')(
        client,
        const NoServerInput(),
      ),
      throwsA(
        isA<RpcProtocolException>().having(
          (error) => error.message,
          'message',
          contains('larger than 64 bytes'),
        ),
      ),
    );
    await expectLater(bodyCancelled.future, completes);
  });

  test('rejects an oversized error without losing its status', () async {
    final bodyCancelled = Completer<void>();
    late final StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onListen: () => body.add(List<int>.filled(65, 0x20)),
      onCancel: bodyCancelled.complete,
    );
    addTearDown(body.close);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse(
          status: 502,
          headers: Headers.single(<String, String>{
            'content-type': 'application/json; charset=utf-8',
          }),
          body: body.stream,
        ),
      ]),
      maxResponseFrameBytes: 64,
    );

    await expectLater(
      const ServerFunctionRef<NoServerInput, Object?>(id: 'read')(
        client,
        const NoServerInput(),
      ),
      throwsA(
        isA<RemoteServerException>().having(
          (error) => error.status,
          'status',
          502,
        ),
      ),
    );
    await expectLater(bodyCancelled.future, completes);
  });

  test('limits each stream frame instead of the complete stream', () async {
    final first = _encodedStreamFrame('café');
    final second = _encodedStreamFrame('again');
    final maxFrameBytes = [
      first.length - 1,
      second.length - 1,
    ].reduce((left, right) => left > right ? left : right);
    final body = <int>[...first, ...second];
    final split = first.length + 3;
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse(
          headers: Headers.single(<String, String>{
            'content-type': 'application/x-ndjson; charset=utf-8',
          }),
          body: Stream<List<int>>.fromIterable(<List<int>>[
            body.sublist(0, split),
            body.sublist(split),
          ]),
        ),
      ]),
      maxResponseFrameBytes: maxFrameBytes,
    );

    final stream = await const ServerStreamFunctionRef<NoServerInput, String>(
      id: 'watch',
    )(client, const NoServerInput());

    expect(await stream.toList(), <String>['café', 'again']);
    expect(body.length, greaterThan(maxFrameBytes));
  });

  test('accepts exact-sized CRLF and CR stream frames', () async {
    final first = _encodedDataFrame('first');
    final second = _encodedDataFrame('second');
    final maxFrameBytes = [
      first.length,
      second.length,
    ].reduce((left, right) => left > right ? left : right);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse(
          headers: Headers.single(<String, String>{
            'content-type': 'application/x-ndjson; charset=utf-8',
          }),
          body: Stream<List<int>>.fromIterable(<List<int>>[
            <int>[...first, 0x0d],
            <int>[0x0a, ...second, 0x0d],
          ]),
        ),
      ]),
      maxResponseFrameBytes: maxFrameBytes,
    );

    final stream = await const ServerStreamFunctionRef<NoServerInput, String>(
      id: 'watch',
    )(client, const NoServerInput());

    expect(await stream.toList(), <String>['first', 'second']);
  });

  test('emits complete frames before cancelling an oversized frame', () async {
    final bodyCancelled = Completer<void>();
    final first = _encodedStreamFrame(1);
    late final StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onListen: () {
        body.add(<int>[...first, ...List<int>.filled(65, 0x20)]);
      },
      onCancel: () {
        bodyCancelled.complete();
        return Future<void>.error(StateError('cleanup failed'));
      },
    );
    addTearDown(body.close);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse(
          headers: Headers.single(<String, String>{
            'content-type': 'application/x-ndjson; charset=utf-8',
          }),
          body: body.stream,
        ),
      ]),
      maxResponseFrameBytes: 64,
    );

    final stream = await const ServerStreamFunctionRef<NoServerInput, int>(
      id: 'watch',
    )(client, const NoServerInput());

    await expectLater(
      stream,
      emitsInOrder(<Object>[
        1,
        emitsError(
          isA<RpcProtocolException>().having(
            (error) => error.message,
            'message',
            contains('larger than 64 bytes'),
          ),
        ),
      ]),
    );
    await expectLater(bodyCancelled.future, completes);
  });

  test('does not flush an oversized unterminated stream frame', () async {
    final bodyCancelled = Completer<void>();
    final encoded = _encodedDataFrame(7);
    late final StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onListen: () {
        body
          ..add(encoded)
          ..add(List<int>.filled(65 - encoded.length, 0x20));
      },
      onCancel: bodyCancelled.complete,
    );
    addTearDown(body.close);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse(
          headers: Headers.single(<String, String>{
            'content-type': 'application/x-ndjson; charset=utf-8',
          }),
          body: body.stream,
        ),
      ]),
      maxResponseFrameBytes: 64,
    );
    final stream = await const ServerStreamFunctionRef<NoServerInput, int>(
      id: 'watch',
    )(client, const NoServerInput());
    final values = <int>[];
    final errors = <Object>[];
    final done = Completer<void>();
    final subscription = stream.listen(
      values.add,
      onError: errors.add,
      onDone: done.complete,
      cancelOnError: false,
    );
    addTearDown(subscription.cancel);

    await expectLater(done.future, completes);

    expect(values, isEmpty);
    expect(errors, hasLength(1));
    expect(errors.single, isA<RpcProtocolException>());
    await expectLater(bodyCancelled.future, completes);
  });

  test('cancels a stream body rejected by a value function', () async {
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        cancelled.complete();
        return Future<void>.error(StateError('cleanup failed'));
      },
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

  test('preserves HTTP status when rejected body cleanup fails', () async {
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        cancelled.complete();
        return Future<void>.error(StateError('cleanup failed'));
      },
    );
    addTearDown(controller.close);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse(
          status: 503,
          headers: Headers.single(<String, String>{
            'content-type': 'application/x-ndjson; charset=utf-8',
          }),
          body: controller.stream,
        ),
      ]),
    );

    await expectLater(
      const ServerStreamFunctionRef<NoServerInput, Object?>(id: 'watch')(
        client,
        const NoServerInput(),
      ),
      throwsA(
        isA<RemoteServerException>().having(
          (error) => error.status,
          'status',
          503,
        ),
      ),
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

  test(
    'consumer cancellation immediately releases an idle stream body',
    () async {
      final bodyStarted = Completer<void>();
      final bodyCancelled = Completer<void>();
      final body = StreamController<List<int>>(
        onListen: bodyStarted.complete,
        onCancel: bodyCancelled.complete,
      );
      addTearDown(body.close);
      final client = RpcClient(
        baseUri: Uri.parse('https://api.example.com'),
        transport: _RecordingTransport(<ServerResponse>[
          ServerResponse(
            headers: Headers.single(<String, String>{
              'content-type': 'application/x-ndjson; charset=utf-8',
            }),
            body: body.stream,
          ),
        ]),
      );

      final stream =
          await const ServerStreamFunctionRef<NoServerInput, Object?>(
            id: 'watch',
          )(client, const NoServerInput());
      final subscription = stream.listen(null);
      await bodyStarted.future;

      await subscription.cancel().timeout(const Duration(seconds: 1));
      await expectLater(bodyCancelled.future, completes);
    },
  );

  test(
    'consumer cancellation stops decoding the current stream chunk',
    () async {
      final bodyCancelled = Completer<void>();
      final body = StreamController<List<int>>(
        sync: true,
        onCancel: bodyCancelled.complete,
      );
      addTearDown(body.close);
      var decoded = 0;
      final client = RpcClient(
        baseUri: Uri.parse('https://api.example.com'),
        transport: _RecordingTransport(<ServerResponse>[
          ServerResponse(
            headers: Headers.single(<String, String>{
              'content-type': 'application/x-ndjson; charset=utf-8',
            }),
            body: body.stream,
          ),
        ]),
      );

      final stream = await ServerStreamFunctionRef<NoServerInput, int>(
        id: 'watch',
        decodeOutput: (value) {
          decoded++;
          return value as int;
        },
      )(client, const NoServerInput());
      final values = <int>[];
      final subscriptionCancelled = Completer<void>();
      late final StreamSubscription<int> subscription;
      subscription = stream.listen((value) {
        values.add(value);
        unawaited(
          subscription.cancel().then((_) => subscriptionCancelled.complete()),
        );
      });

      body.add(<int>[..._encodedStreamFrame(1), ..._encodedStreamFrame(2)]);

      await subscriptionCancelled.future.timeout(const Duration(seconds: 1));
      await expectLater(bodyCancelled.future, completes);
      expect(values, <int>[1]);
      expect(decoded, 1);
    },
  );

  test('cancels a value body from a custom transport', () async {
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
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse(
          headers: Headers.single(<String, String>{
            'content-type': 'application/json; charset=utf-8',
          }),
          body: body.stream,
        ),
      ]),
    );
    final cancelled = Completer<void>();

    final uncaught = <Object>[];
    await runZonedGuarded<Future<void>>(() async {
      final call = const ServerFunctionRef<NoServerInput, Object?>(id: 'read')(
        client,
        const NoServerInput(),
        cancelled: cancelled.future,
      );
      await bodyStarted.future;
      cancelled.complete();

      await expectLater(call, throwsA(isA<RpcCancelledException>()));
      await expectLater(bodyCancelled.future, completes);
    }, (error, _) => uncaught.add(error));
    await Future<void>.delayed(Duration.zero);
    expect(uncaught, isEmpty);
  });

  test(
    'reports a synchronous response listen failure without hanging',
    () async {
      final body = StreamController<List<int>>();
      final firstSubscription = body.stream.listen(null);
      addTearDown(() async {
        await firstSubscription.cancel();
        await body.close();
      });
      final client = RpcClient(
        baseUri: Uri.parse('https://api.example.com'),
        transport: _RecordingTransport(<ServerResponse>[
          ServerResponse(
            headers: Headers.single(<String, String>{
              'content-type': 'application/json; charset=utf-8',
            }),
            body: body.stream,
          ),
        ]),
      );
      final cancelled = Completer<void>();

      final call = const ServerFunctionRef<NoServerInput, Object?>(id: 'read')(
        client,
        const NoServerInput(),
        cancelled: cancelled.future,
      );
      await expectLater(
        call.timeout(const Duration(seconds: 1)),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('reports invalid response bytes without hanging', () async {
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse(
          headers: Headers.single(<String, String>{
            'content-type': 'application/json; charset=utf-8',
          }),
          body: Stream<List<int>>.value(_ThrowingByteList()),
        ),
      ]),
    );

    final call = const ServerFunctionRef<NoServerInput, Object?>(id: 'read')(
      client,
      const NoServerInput(),
    );
    await expectLater(
      call.timeout(const Duration(seconds: 1)),
      throwsA(isA<StateError>()),
    );
  });

  test('cancels a stream body from a custom transport', () async {
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
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[
        ServerResponse(
          headers: Headers.single(<String, String>{
            'content-type': 'application/x-ndjson; charset=utf-8',
          }),
          body: body.stream,
        ),
      ]),
    );
    final cancelled = Completer<void>();
    final uncaught = <Object>[];
    await runZonedGuarded<Future<void>>(() async {
      final stream =
          await const ServerStreamFunctionRef<NoServerInput, Object?>(
            id: 'watch',
          )(client, const NoServerInput(), cancelled: cancelled.future);
      final error = Completer<Object>();
      final subscription = stream.listen(
        null,
        onError: (Object value) => error.complete(value),
      );
      addTearDown(subscription.cancel);
      await bodyStarted.future;

      cancelled.complete();
      expect(await error.future, isA<RpcCancelledException>());
      await expectLater(bodyCancelled.future, completes);
    }, (error, _) => uncaught.add(error));
    await Future<void>.delayed(Duration.zero);
    expect(uncaught, isEmpty);
  });

  test('leaves raw server responses to the caller', () async {
    final response = ServerResponse.text('Unauthorized', status: 401);
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: _RecordingTransport(<ServerResponse>[response]),
      maxResponseFrameBytes: 1,
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

List<int> _encodedDataFrame(Object? data) => utf8.encode(
  jsonEncode(<String, Object?>{'version': 1, 'type': 'data', 'data': data}),
);

List<int> _encodedStreamFrame(Object? data) => <int>[
  ..._encodedDataFrame(data),
  0x0a,
];

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

typedef _Post = ({int id, String title});

final class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
    required this.cancelled,
  });

  final HttpMethod method;
  final Uri uri;
  final Headers headers;
  final String body;
  final Future<void>? cancelled;
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
        cancelled: request.cancelled,
      ),
    );
    return _responses.removeFirst();
  }
}

final class _ThrowingByteList extends ListBase<int> {
  @override
  int get length => 1;

  @override
  set length(int value) => throw UnsupportedError('immutable');

  @override
  int operator [](int index) => throw StateError('invalid response bytes');

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('immutable');
}

final class _ServerTransport implements RpcTransport {
  const _ServerTransport(this.server);

  final Server server;

  @override
  Future<ServerResponse> send(ServerRequest request) => server.handle(request);
}
