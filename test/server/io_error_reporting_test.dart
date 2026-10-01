import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/server_io.dart';
import 'package:test/test.dart';

void main() {
  test(
    'metadata failure rebuilds a clean 500 before report completion',
    () async {
      final cleanupFailure = StateError('secondary body cancellation failed');
      final cleanupStackTrace = StackTrace.current;
      final cancelled = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled.complete();
          return Future<void>.error(cleanupFailure, cleanupStackTrace);
        },
      );
      addTearDown(() async {
        if (!body.isClosed) await body.close();
      });
      final releaseReporter = Completer<void>();
      addTearDown(() {
        if (!releaseReporter.isCompleted) releaseReporter.complete();
      });
      final reporterStarted =
          Completer<
            ({ServerRequest request, Object error, StackTrace stackTrace})
          >();
      final reporterFinished = Completer<void>();
      ServerRequest? handledRequest;

      final server = await IoServer.bind(
        (request) async {
          handledRequest = request;
          return ServerResponse(
            status: HttpStatus.created,
            reason: 'Leaky reason',
            headers: Headers()
              ..set('x-leak', 'secret')
              ..set('set-cookie', 'session=secret')
              ..set('cache-control', 'public, max-age=3600')
              ..set('content-length', '999')
              ..set('invalid\nname', 'value'),
            body: body.stream,
          );
        },
        onError: (request, error, stackTrace) async {
          reporterStarted.complete((
            request: request,
            error: error,
            stackTrace: stackTrace,
          ));
          await releaseReporter.future;
          reporterFinished.complete();
        },
        port: 0,
      );
      addTearDown(server.close);
      final client = HttpClient();
      addTearDown(client.close);

      final outgoing = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/metadata'),
      );
      final response = await outgoing.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final report = await reporterStarted.future.timeout(
        const Duration(seconds: 2),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.reasonPhrase, 'Internal Server Error');
      expect(response.headers.value('x-leak'), isNull);
      expect(response.headers.value(HttpHeaders.setCookieHeader), isNull);
      expect(response.cookies, isEmpty);
      expect(response.headers.value(HttpHeaders.cacheControlHeader), isNull);
      expect(response.headers.contentType?.mimeType, ContentType.text.mimeType);
      expect(response.headers.contentType?.charset, 'utf-8');
      expect(response.contentLength, utf8.encode(responseBody).length);
      expect(responseBody, 'Internal server error.');
      expect(report.request, same(handledRequest));
      expect(report.error, isNot(same(cleanupFailure)));
      expect(report.stackTrace.toString(), isNotEmpty);
      expect(cancelled.isCompleted, isTrue);
      expect(reporterFinished.isCompleted, isFalse);

      releaseReporter.complete();
      await reporterFinished.future.timeout(const Duration(seconds: 2));
    },
  );

  test(
    'raw omitted-body cleanup reports once without changing status',
    () async {
      final failure = StateError('raw body cancellation failed');
      final failureStackTrace = StackTrace.current;
      final body = StreamController<List<int>>(
        onCancel: () => Future<void>.error(failure, failureStackTrace),
      );
      addTearDown(() async {
        if (!body.isClosed) await body.close();
      });
      final reports = <Object>[];
      final reported = Completer<void>();
      final server = await IoServer.bind(
        (_) async =>
            ServerResponse(status: HttpStatus.noContent, body: body.stream),
        onError: (_, error, _) {
          reports.add(error);
          reported.complete();
        },
        port: 0,
      );
      addTearDown(server.close);
      final client = HttpClient();
      addTearDown(client.close);

      final outgoing = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/raw'),
      );
      final response = await outgoing.close();
      await response.drain<void>();
      await reported.future.timeout(const Duration(seconds: 2));

      expect(response.statusCode, HttpStatus.noContent);
      expect(reports, <Object>[failure]);
    },
  );

  test('generated Server owns omitted-body cleanup exactly once', () async {
    final failure = StateError('server body cancellation failed');
    final failureStackTrace = StackTrace.current;
    final body = StreamController<List<int>>(
      onCancel: () => Future<void>.error(failure, failureStackTrace),
    );
    addTearDown(() async {
      if (!body.isClosed) await body.close();
    });
    final reports = <Object>[];
    final reported = Completer<void>();
    final appServer = Server(
      routes: const [],
      middleware: <Middleware>[
        (_, _) async =>
            ServerResponse(status: HttpStatus.noContent, body: body.stream),
      ],
      onError: (_, error, _) {
        reports.add(error);
        if (!reported.isCompleted) reported.complete();
      },
    );
    final server = await IoServer.bind(
      appServer.handler,
      onError: appServer.onError,
      port: 0,
    );
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);

    final outgoing = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/server'),
    );
    final response = await outgoing.close();
    await response.drain<void>();
    await reported.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);

    expect(response.statusCode, HttpStatus.noContent);
    expect(reports, <Object>[failure]);
  });

  test(
    'handler failures already reported by Server are not duplicated',
    () async {
      final failure = StateError('module setup failed');
      final reports = <Object>[];
      final appServer = Server(
        routes: const [],
        modules: () => throw failure,
        onError: (_, error, _) => reports.add(error),
      );
      final server = await IoServer.bind(
        appServer.handler,
        onError: appServer.onError,
        port: 0,
      );
      addTearDown(server.close);
      final client = HttpClient();
      addTearDown(client.close);

      final outgoing = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/setup'),
      );
      final response = await outgoing.close();
      final body = await response.transform(utf8.decoder).join();

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(body, 'Internal server error.');
      expect(reports, <Object>[failure]);
    },
  );

  test(
    'source-stream failure stays Server-owned after response starts',
    () async {
      final failure = StateError('response source failed');
      final reports = <Object>[];
      final reported = Completer<void>();

      Stream<List<int>> failingBody() async* {
        yield utf8.encode('prefix');
        throw failure;
      }

      final appServer = Server(
        routes: const [],
        middleware: <Middleware>[
          (_, _) async => ServerResponse(body: failingBody()),
        ],
        onError: (_, error, _) {
          reports.add(error);
          if (!reported.isCompleted) reported.complete();
        },
      );
      final server = await IoServer.bind(
        appServer.handler,
        onError: appServer.onError,
        port: 0,
      );
      addTearDown(server.close);
      final client = HttpClient();
      addTearDown(client.close);
      final bytes = <int>[];

      final outgoing = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/stream'),
      );
      final response = await outgoing.close();
      try {
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
      } on Object {
        // A committed response can only terminate the connection.
      }
      await reported.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);

      expect(utf8.decode(bytes), isNot(contains('Internal server error.')));
      expect(reports, <Object>[failure]);
    },
  );

  test('development proxy upstream failure is adapter-owned', () async {
    final directory = await Directory.systemTemp.createTemp(
      'odroe-proxy-error-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamSubscription = upstream.listen((socket) => socket.destroy());
    addTearDown(() async {
      await upstreamSubscription.cancel();
      await upstream.close();
    });
    final originFile = File('${directory.path}/origin');
    await originFile.writeAsString('http://127.0.0.1:${upstream.port}');
    final reports =
        <({ServerRequest request, Object error, StackTrace stackTrace})>[];
    var handlerCalls = 0;
    final server = await IoServer.bind(
      (_) async {
        handlerCalls++;
        return ServerResponse.text('unexpected');
      },
      onError: (request, error, stackTrace) =>
          reports.add((request: request, error: error, stackTrace: stackTrace)),
      port: 0,
      developmentProxyOriginFile: originFile,
    );
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);

    final outgoing = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/main.dart.js'),
    );
    final response = await outgoing.close();
    final body = await response.transform(utf8.decoder).join();

    expect(response.statusCode, HttpStatus.internalServerError);
    expect(body, 'Internal server error.');
    expect(handlerCalls, 0);
    expect(reports, hasLength(1));
    expect(reports.single.request.uri.path, '/main.dart.js');
    expect(
      reports.single.error,
      anyOf(isA<SocketException>(), isA<HttpException>()),
    );
  });

  test('development proxy removes forbidden 204 framing', () async {
    final directory = await Directory.systemTemp.createTemp(
      'odroe-proxy-framing-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamSubscription = upstream.listen((request) async {
      request.response
        ..statusCode = HttpStatus.noContent
        ..headers.chunkedTransferEncoding = false;
      await request.response.addStream(const Stream<List<int>>.empty());
      await request.response.close();
    });
    addTearDown(() async {
      await upstreamSubscription.cancel();
      await upstream.close(force: true);
    });
    final originFile = File('${directory.path}/origin');
    await originFile.writeAsString('http://127.0.0.1:${upstream.port}');
    final reports = <Object>[];
    var handlerCalls = 0;
    final server = await IoServer.bind(
      (_) async {
        handlerCalls++;
        return ServerResponse.text('unexpected');
      },
      onError: (_, error, _) => reports.add(error),
      port: 0,
      developmentProxyOriginFile: originFile,
    );
    addTearDown(server.close);

    for (final method in <String>['GET', 'HEAD']) {
      final response = await _rawResponse(server.port, method, '/main.dart.js');
      expect(
        response.statusLine,
        startsWith('HTTP/1.1 ${HttpStatus.noContent} '),
        reason: method,
      );
      expect(
        response.headers[HttpHeaders.contentLengthHeader],
        isNull,
        reason: method,
      );
      expect(
        response.headers[HttpHeaders.transferEncodingHeader],
        isNull,
        reason: method,
      );
      expect(response.body, isEmpty, reason: method);
    }
    expect(handlerCalls, 0);
    expect(reports, isEmpty);
  });

  test(
    'malformed forwarded authority is a 400 before static dispatch',
    () async {
      final public = await Directory.systemTemp.createTemp('odroe-authority-');
      addTearDown(() => public.delete(recursive: true));
      await File('${public.path}/dynamic').writeAsString('static');
      final reports = <Object>[];
      var handlerCalls = 0;
      final server = await IoServer.bind(
        (_) async {
          handlerCalls++;
          return ServerResponse.text('ok');
        },
        onError: (_, error, _) => reports.add(error),
        port: 0,
        publicDirectory: public,
      );
      addTearDown(server.close);
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      addTearDown(socket.destroy);
      socket.add(
        utf8.encode(
          'GET /dynamic HTTP/1.1\r\n'
          'Host: 127.0.0.1:${server.port}\r\n'
          'X-Forwarded-Host: [broken\r\n'
          'Connection: close\r\n'
          '\r\n',
        ),
      );
      await socket.flush();
      final rawResponse = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();

      expect(rawResponse, startsWith('HTTP/1.1 400 Bad Request'));
      expect(rawResponse, contains('Bad request.'));
      expect(handlerCalls, 0);
      expect(reports, isEmpty);

      final client = HttpClient();
      addTearDown(client.close);
      final outgoing = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/healthy'),
      );
      final response = await outgoing.close();
      expect(await response.transform(utf8.decoder).join(), 'ok');
      expect(handlerCalls, 1);
    },
  );

  test('static close underflow remains adapter-owned', () async {
    final public = await Directory.systemTemp.createTemp(
      'odroe-static-underflow-',
    );
    addTearDown(() => public.delete(recursive: true));
    final asset = File('${public.path}/large.bin');
    final writer = await asset.open(mode: FileMode.write);
    await writer.truncate(64 * 1024 * 1024);
    await writer.close();

    final reports =
        <({ServerRequest request, Object error, StackTrace stackTrace})>[];
    final reported = Completer<void>();
    var handlerCalls = 0;
    final server = await IoServer.bind(
      (_) async {
        handlerCalls++;
        return ServerResponse.text('unexpected');
      },
      onError: (request, error, stackTrace) {
        reports.add((request: request, error: error, stackTrace: stackTrace));
        if (!reported.isCompleted) reported.complete();
      },
      port: 0,
      publicDirectory: public,
      compressStaticAssets: false,
    );
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);
    final outgoing = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/large.bin'),
    );
    final response = await outgoing.close();
    expect(response.contentLength, 64 * 1024 * 1024);

    final firstChunk = Completer<void>();
    final responseDone = Completer<void>();
    Object? clientFailure;
    late final StreamSubscription<List<int>> subscription;
    subscription = response.listen(
      (_) {
        if (!firstChunk.isCompleted) {
          firstChunk.complete();
          subscription.pause();
        }
      },
      onError: (Object error, StackTrace _) {
        clientFailure = error;
        if (!responseDone.isCompleted) responseDone.complete();
      },
      onDone: () {
        if (!responseDone.isCompleted) responseDone.complete();
      },
      cancelOnError: true,
    );
    addTearDown(subscription.cancel);
    await firstChunk.future.timeout(const Duration(seconds: 2));
    await asset.writeAsBytes(const <int>[0], flush: true);
    subscription.resume();

    await responseDone.future.timeout(const Duration(seconds: 5));
    await reported.future.timeout(const Duration(seconds: 5));
    expect(clientFailure, isNotNull);
    expect(handlerCalls, 0);
    expect(reports, hasLength(1));
    expect(reports.single.request.method, HttpMethod.get);
    expect(reports.single.request.uri.path, '/large.bin');
    expect('${reports.single.error}', contains('contentLength'));
  });

  test('client disconnect does not report response delivery', () async {
    final reports = <Object>[];
    final handlerStarted = Completer<void>();
    final releaseHandler = Completer<void>();
    final bodyFinished = Completer<void>();
    final bodyBuffered = Completer<void>();
    final server = await IoServer.bind(
      (request) async {
        if (request.uri.path == '/healthy') return ServerResponse.text('ok');
        handlerStarted.complete();
        await releaseHandler.future;

        Stream<List<int>> body() async* {
          try {
            final chunk = List<int>.filled(64 * 1024, 1);
            for (var index = 0; index < 60000; index++) {
              yield chunk;
              if (index == 7) bodyBuffered.complete();
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
          } finally {
            bodyFinished.complete();
          }
        }

        return ServerResponse(body: body());
      },
      onError: (_, error, _) => reports.add(error),
      port: 0,
    );
    addTearDown(server.close);
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
    );
    addTearDown(socket.destroy);
    socket.add(
      utf8.encode(
        'GET /disconnect HTTP/1.1\r\n'
        'Host: 127.0.0.1:${server.port}\r\n'
        '\r\n',
      ),
    );
    await socket.flush();
    await handlerStarted.future.timeout(const Duration(seconds: 2));
    final responseStarted = Completer<void>();
    late final StreamSubscription<List<int>> responseSubscription;
    responseSubscription = socket.listen((_) {
      if (!responseStarted.isCompleted) {
        responseStarted.complete();
        responseSubscription.pause();
      }
    });
    addTearDown(responseSubscription.cancel);
    releaseHandler.complete();
    await responseStarted.future.timeout(const Duration(seconds: 2));
    await bodyBuffered.future.timeout(const Duration(seconds: 2));
    socket.destroy();

    await bodyFinished.future.timeout(const Duration(seconds: 5));
    expect(reports, isEmpty);

    final client = HttpClient();
    addTearDown(client.close);
    final outgoing = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/healthy'),
    );
    final response = await outgoing.close();
    expect(await response.transform(utf8.decoder).join(), 'ok');
    expect(reports, isEmpty);
  });

  test('clean sources report Content-Length framing failures', () async {
    Future<Object> runCase(int contentLength, List<int> bytes) async {
      final reports = <Object>[];
      final reported = Completer<void>();
      final server = await IoServer.bind(
        (_) async => ServerResponse(
          headers: Headers()
            ..set(HttpHeaders.contentLengthHeader, '$contentLength'),
          body: Stream<List<int>>.value(bytes),
        ),
        onError: (_, error, _) {
          reports.add(error);
          if (!reported.isCompleted) reported.complete();
        },
        port: 0,
      );
      final client = HttpClient();
      try {
        final outgoing = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/framing'),
        );
        outgoing.persistentConnection = false;
        try {
          final response = await outgoing.close();
          await response.drain<void>().timeout(const Duration(seconds: 2));
        } on Object {
          // Invalid framing terminates the client-side response.
        }
        await reported.future.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(Duration.zero);
        expect(reports, hasLength(1));
        return reports.single;
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    }

    final overflow = await runCase(1, <int>[1, 2]);
    final underflow = await runCase(3, <int>[1, 2]);

    expect('$overflow', contains('contentLength'));
    expect('$underflow', contains('contentLength'));
  });

  test('bodyless response framing follows HTTP status semantics', () async {
    final reports = <Object>[];
    final server = await IoServer.bind(
      (request) async {
        final segments = request.uri.pathSegments;
        final status = int.parse(segments.first);
        final headers = Headers();
        if (segments.last == 'length') {
          headers.set(HttpHeaders.contentLengthHeader, '3');
        } else {
          headers.set(HttpHeaders.transferEncodingHeader, 'chunked');
        }
        return ServerResponse(
          status: status,
          headers: headers,
          body: Stream<List<int>>.value(<int>[1, 2, 3]),
        );
      },
      onError: (_, error, _) => reports.add(error),
      port: 0,
    );
    addTearDown(server.close);

    final cases =
        <
          ({
            String method,
            int status,
            String framing,
            String? contentLength,
            bool transferEncoding,
          })
        >[
          (
            method: 'HEAD',
            status: HttpStatus.ok,
            framing: 'length',
            contentLength: '3',
            transferEncoding: false,
          ),
          (
            method: 'HEAD',
            status: HttpStatus.ok,
            framing: 'transfer',
            contentLength: null,
            transferEncoding: true,
          ),
          for (final method in <String>['GET', 'HEAD'])
            for (final framing in <String>['length', 'transfer'])
              (
                method: method,
                status: 103,
                framing: framing,
                contentLength: null,
                transferEncoding: false,
              ),
          for (final method in <String>['GET', 'HEAD'])
            for (final framing in <String>['length', 'transfer'])
              (
                method: method,
                status: HttpStatus.noContent,
                framing: framing,
                contentLength: null,
                transferEncoding: false,
              ),
          for (final method in <String>['GET', 'HEAD'])
            for (final framing in <String>['length', 'transfer'])
              (
                method: method,
                status: HttpStatus.resetContent,
                framing: framing,
                contentLength: '0',
                transferEncoding: false,
              ),
          (
            method: 'GET',
            status: HttpStatus.notModified,
            framing: 'length',
            contentLength: null,
            transferEncoding: false,
          ),
          (
            method: 'GET',
            status: HttpStatus.notModified,
            framing: 'transfer',
            contentLength: null,
            transferEncoding: false,
          ),
          (
            method: 'HEAD',
            status: HttpStatus.notModified,
            framing: 'length',
            contentLength: '3',
            transferEncoding: false,
          ),
          (
            method: 'HEAD',
            status: HttpStatus.notModified,
            framing: 'transfer',
            contentLength: null,
            transferEncoding: true,
          ),
        ];
    for (final testCase in cases) {
      final response = await _rawResponse(
        server.port,
        testCase.method,
        '/${testCase.status}/${testCase.framing}',
      );
      final reason =
          '${testCase.method} ${testCase.status} ${testCase.framing}';
      expect(
        response.statusLine,
        startsWith('HTTP/1.1 ${testCase.status} '),
        reason: reason,
      );
      expect(
        response.headers[HttpHeaders.contentLengthHeader],
        testCase.contentLength,
        reason: reason,
      );
      expect(
        response.headers[HttpHeaders.transferEncodingHeader],
        testCase.transferEncoding ? 'chunked' : isNull,
        reason: reason,
      );
      expect(response.body, isEmpty, reason: reason);
    }

    final chunked = await _rawResponse(
      server.port,
      'GET',
      '/${HttpStatus.ok}/transfer',
    );
    expect(chunked.headers[HttpHeaders.contentLengthHeader], isNull);
    expect(chunked.headers[HttpHeaders.transferEncodingHeader], 'chunked');
    expect(chunked.body.codeUnits, <int>[
      0x33,
      0x0d,
      0x0a,
      0x01,
      0x02,
      0x03,
      0x0d,
      0x0a,
      0x30,
      0x0d,
      0x0a,
      0x0d,
      0x0a,
    ]);

    expect(reports, isEmpty);
  });
}

Future<({String statusLine, Map<String, String> headers, String body})>
_rawResponse(int port, String method, String path) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  try {
    socket.add(
      utf8.encode(
        '$method $path HTTP/1.1\r\n'
        'Host: 127.0.0.1:$port\r\n'
        'Connection: close\r\n'
        '\r\n',
      ),
    );
    await socket.flush();
    final bytes = await socket
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk))
        .timeout(const Duration(seconds: 2));
    final raw = latin1.decode(bytes);
    final boundary = raw.indexOf('\r\n\r\n');
    expect(boundary, greaterThanOrEqualTo(0));
    final lines = raw.substring(0, boundary).split('\r\n');
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final separator = line.indexOf(':');
      if (separator < 0) continue;
      headers[line.substring(0, separator).toLowerCase()] = line
          .substring(separator + 1)
          .trim();
    }
    return (
      statusLine: lines.first,
      headers: headers,
      body: raw.substring(boundary + 4),
    );
  } finally {
    socket.destroy();
  }
}
