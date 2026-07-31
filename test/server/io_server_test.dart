import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/document.dart';
import 'package:odroe/router.dart';
import 'package:odroe/rpc.dart';
import 'package:odroe/server_io.dart';
import 'package:test/test.dart';

void main() {
  test('IO adapter sends only the bounded typed function error', () async {
    const maxFrameBytes = 64;
    final app = Server(
      routes: const [],
      functions: <String, ServerFunctionBinding>{
        'large': ServerFunctionBinding(
          ServerFunction<NoServerInput, String>(handler: (_) => 'x' * 4096),
        ),
      },
      maxFunctionResponseFrameBytes: maxFrameBytes,
    );
    final server = await IoServer.bind(app.handle, port: 0);
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);
    final uri = Uri.parse(
      'http://127.0.0.1:${server.port}/__odroe/functions/large',
    );

    final request = await client.postUrl(uri);
    request.headers
      ..contentType = ContentType.json
      ..set('origin', uri.origin);
    request.write('{"data":null}');
    final response = await request.close();
    final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
      all.addAll(chunk);
      return all;
    });

    expect(response.statusCode, HttpStatus.internalServerError);
    expect(bytes.length, lessThanOrEqualTo(maxFrameBytes));
    expect(jsonDecode(utf8.decode(bytes)), containsPair('type', 'error'));
    expect(utf8.decode(bytes), isNot(contains('x' * 128)));
  });

  test('IO adapter serves assets without escaping the public root', () async {
    final public = await Directory.systemTemp.createTemp('odroe-public-');
    final outside = await Directory.systemTemp.createTemp('odroe-private-');
    addTearDown(() => public.delete(recursive: true));
    addTearDown(() => outside.delete(recursive: true));
    await File('${public.path}/flutter_bootstrap.js').writeAsString('boot');
    await Directory('${public.path}/nested').create();
    await File('${public.path}/nested/inside.txt').writeAsString('inside');
    final replaceable = File('${public.path}/replaceable.txt');
    await replaceable.writeAsString('public');
    await File('${outside.path}/secret.txt').writeAsString('secret');
    if (!Platform.isWindows) {
      await Link(
        '${public.path}/secret.txt',
      ).create('${outside.path}/secret.txt');
    }

    final app = Server(
      routes: <RouteNode>[AppRoute<NoParams, NoSearch, NoData>(path: '/')],
      renderer: const DocumentRenderer().call,
    );
    final server = await IoServer.bind(
      app.handle,
      port: 0,
      publicDirectory: public,
    );
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);
    final base = Uri.parse('http://127.0.0.1:${server.port}');

    final asset = await client.getUrl(base.resolve('/flutter_bootstrap.js'));
    final assetResponse = await asset.close();
    expect(
      await assetResponse.transform(SystemEncoding().decoder).join(),
      'boot',
    );

    final encodedSeparator = await client.getUrl(
      base.resolve('/nested%2Finside.txt'),
    );
    final encodedSeparatorResponse = await encodedSeparator.close();
    expect(encodedSeparatorResponse.statusCode, HttpStatus.notFound);
    expect(
      await encodedSeparatorResponse.transform(utf8.decoder).join(),
      isNot(contains('inside')),
    );

    if (!Platform.isWindows) {
      final first = await client.getUrl(base.resolve('/replaceable.txt'));
      final firstResponse = await first.close();
      expect(await firstResponse.transform(utf8.decoder).join(), 'public');

      await replaceable.delete();
      await Link(replaceable.path).create('${outside.path}/secret.txt');
      final replaced = await client.getUrl(base.resolve('/replaceable.txt'));
      final replacedResponse = await replaced.close();
      expect(replacedResponse.statusCode, HttpStatus.notFound);
      expect(
        await replacedResponse.transform(utf8.decoder).join(),
        isNot(contains('secret')),
      );
    }

    final route = await client.getUrl(base.resolve('/'));
    route.headers.set(HttpHeaders.acceptHeader, 'text/html');
    final routeResponse = await route.close();
    expect(routeResponse.statusCode, HttpStatus.ok);
    expect(
      routeResponse.headers.contentType?.mimeType,
      ContentType.html.mimeType,
    );

    if (!Platform.isWindows) {
      final secret = await client.getUrl(base.resolve('/secret.txt'));
      secret.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final secretResponse = await secret.close();
      expect(secretResponse.statusCode, HttpStatus.notFound);
      expect(
        await secretResponse.transform(SystemEncoding().decoder).join(),
        isNot(contains('secret')),
      );
    }
  });

  test('IO adapter serves prerendered indexes at canonical routes', () async {
    final public = await Directory.systemTemp.createTemp('odroe-routes-');
    final outside = await Directory.systemTemp.createTemp('odroe-routes-out-');
    addTearDown(() => public.delete(recursive: true));
    addTearDown(() => outside.delete(recursive: true));
    await File('${public.path}/index.html').writeAsString('static root');
    await Directory('${public.path}/docs').create();
    await File('${public.path}/docs/index.html').writeAsString('static docs');
    await Directory('${public.path}/release.v1').create();
    await File(
      '${public.path}/release.v1/index.html',
    ).writeAsString('static release');
    await File('${public.path}/robots').writeAsString('static exact');
    await File('${outside.path}/index.html').writeAsString('private');
    if (!Platform.isWindows) {
      await Link('${public.path}/escape').create(outside.path);
    }

    var handlerCalls = 0;
    final server = await IoServer.bind(
      (request) async {
        handlerCalls++;
        return ServerResponse.text('dynamic ${request.uri.path}');
      },
      port: 0,
      publicDirectory: public,
    );
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);
    final base = Uri.parse('http://127.0.0.1:${server.port}');

    Future<({HttpClientResponse response, String body})> get(
      String path, {
      String? accept,
    }) async {
      final request = await client.getUrl(base.resolve(path));
      if (accept != null) {
        request.headers.set(HttpHeaders.acceptHeader, accept);
      }
      final response = await request.close();
      return (
        response: response,
        body: await response.transform(utf8.decoder).join(),
      );
    }

    for (final page in <(String, String)>[
      ('/', 'static root'),
      ('/docs', 'static docs'),
      ('/docs/', 'static docs'),
      ('/release.v1', 'static release'),
      ('/release.v1/', 'static release'),
      ('/robots', 'static exact'),
    ]) {
      final result = await get(page.$1);
      expect(result.response.statusCode, HttpStatus.ok, reason: page.$1);
      expect(result.body, page.$2, reason: page.$1);
      expect(
        result.response.headers.contentType?.mimeType,
        page.$1 == '/robots'
            ? ContentType.binary.mimeType
            : ContentType.html.mimeType,
        reason: page.$1,
      );
    }
    expect(handlerCalls, 0);

    final docs = await get('/docs');
    final etag = docs.response.headers.value(HttpHeaders.etagHeader);
    expect(docs.response.headers.value(HttpHeaders.varyHeader), 'Accept');
    final head = await client.openUrl('HEAD', base.resolve('/docs'));
    final headResponse = await head.close();
    expect(headResponse.statusCode, HttpStatus.ok);
    expect(headResponse.headers.value(HttpHeaders.etagHeader), etag);
    expect(headResponse.contentLength, 'static docs'.length);
    expect(await headResponse.toList(), isEmpty);
    expect(handlerCalls, 0);

    final conditional = await client.getUrl(base.resolve('/docs'));
    conditional.headers.set(HttpHeaders.ifNoneMatchHeader, etag!);
    final notModified = await conditional.close();
    expect(notModified.statusCode, HttpStatus.notModified);
    expect(notModified.headers.value(HttpHeaders.varyHeader), 'Accept');
    expect(await notModified.toList(), isEmpty);
    expect(handlerCalls, 0);

    final json = await client.getUrl(base.resolve('/docs'));
    json.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final jsonResponse = await json.close();
    expect(jsonResponse.statusCode, HttpStatus.ok);
    expect(await jsonResponse.transform(utf8.decoder).join(), 'dynamic /docs');
    expect(handlerCalls, 1);

    for (final accept in <String>[
      'text/*',
      '*/*',
      'application/json;q=0, */*;q=1',
    ]) {
      final result = await get('/docs', accept: accept);
      expect(result.body, 'static docs', reason: accept);
    }
    expect(handlerCalls, 1);

    for (final accept in <String>[
      'text/plain',
      'text/html;q=0',
      'application/json;q=1, text/html;q=0.5',
    ]) {
      final result = await get('/docs', accept: accept);
      expect(result.body, 'dynamic /docs', reason: accept);
    }
    expect(handlerCalls, 4);

    final callsBeforeMissing = handlerCalls;
    final missingRoutes = <String>[
      '/missing.css',
      if (!Platform.isWindows) '/escape',
    ];
    for (final route in missingRoutes) {
      final result = await get(route);
      expect(result.body, 'dynamic $route', reason: route);
    }
    expect(handlerCalls, callsBeforeMissing + missingRoutes.length);
  });

  test('IO adapter revalidates static assets without guessed hashes', () async {
    final public = await Directory.systemTemp.createTemp('odroe-cache-');
    addTearDown(() => public.delete(recursive: true));
    final asset = File('${public.path}/app.deadbeef.mjs');
    await asset.writeAsString('version one');
    final server = await IoServer.bind(
      (_) async => ServerResponse.text('missing', status: HttpStatus.notFound),
      port: 0,
      publicDirectory: public,
    );
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);
    final uri = Uri.parse('http://127.0.0.1:${server.port}/app.deadbeef.mjs');

    final first = await client.getUrl(uri);
    final firstResponse = await first.close();
    final etag = firstResponse.headers.value(HttpHeaders.etagHeader);
    final lastModified = firstResponse.headers.value(
      HttpHeaders.lastModifiedHeader,
    );
    expect(firstResponse.statusCode, HttpStatus.ok);
    expect(
      firstResponse.headers.value(HttpHeaders.cacheControlHeader),
      'no-cache',
    );
    expect(etag, isNotNull);
    expect(lastModified, isNotNull);
    expect(firstResponse.headers.contentType?.mimeType, 'text/javascript');
    expect(await firstResponse.transform(utf8.decoder).join(), 'version one');

    final head = await client.openUrl('HEAD', uri);
    final headResponse = await head.close();
    expect(headResponse.statusCode, HttpStatus.ok);
    expect(headResponse.contentLength, 'version one'.length);
    expect(headResponse.headers.value(HttpHeaders.etagHeader), etag);
    expect(await headResponse.toList(), isEmpty);

    final byEtag = await client.getUrl(uri);
    byEtag.headers.set(HttpHeaders.ifNoneMatchHeader, etag!);
    final etagResponse = await byEtag.close();
    expect(etagResponse.statusCode, HttpStatus.notModified);
    expect(etagResponse.headers.value(HttpHeaders.etagHeader), etag);
    expect(await etagResponse.toList(), isEmpty);

    final repeatedEtag = await client.getUrl(uri);
    repeatedEtag.headers
      ..add(HttpHeaders.ifNoneMatchHeader, '"different"')
      ..add(HttpHeaders.ifNoneMatchHeader, etag.substring(2));
    final repeatedEtagResponse = await repeatedEtag.close();
    expect(repeatedEtagResponse.statusCode, HttpStatus.notModified);
    expect(await repeatedEtagResponse.toList(), isEmpty);

    final byDate = await client.getUrl(uri);
    byDate.headers.set(HttpHeaders.ifModifiedSinceHeader, lastModified!);
    final dateResponse = await byDate.close();
    expect(dateResponse.statusCode, HttpStatus.notModified);
    expect(await dateResponse.toList(), isEmpty);

    final etagPrecedence = await client.getUrl(uri);
    etagPrecedence.headers
      ..set(HttpHeaders.ifNoneMatchHeader, '"different"')
      ..set(HttpHeaders.ifModifiedSinceHeader, lastModified);
    final etagPrecedenceResponse = await etagPrecedence.close();
    expect(etagPrecedenceResponse.statusCode, HttpStatus.ok);
    expect(
      await etagPrecedenceResponse.transform(utf8.decoder).join(),
      'version one',
    );

    await asset.writeAsString('version two, changed');
    final changed = await client.getUrl(uri);
    changed.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
    final changedResponse = await changed.close();
    expect(changedResponse.statusCode, HttpStatus.ok);
    expect(
      changedResponse.headers.value(HttpHeaders.etagHeader),
      isNot(equals(etag)),
    );
    expect(
      await changedResponse.transform(utf8.decoder).join(),
      'version two, changed',
    );
  });

  test('IO adapter streams large static assets with optional gzip', () async {
    final public = await Directory.systemTemp.createTemp('odroe-gzip-');
    addTearDown(() => public.delete(recursive: true));
    final source = List<String>.filled(
      2048,
      'One package, every product layer.\n',
    ).join();
    final sourceBytes = utf8.encode(source);
    await File('${public.path}/main.dart.js').writeAsBytes(sourceBytes);
    final server = await IoServer.bind(
      (_) async => ServerResponse.text('missing', status: HttpStatus.notFound),
      port: 0,
      publicDirectory: public,
    );
    addTearDown(server.close);
    final uri = Uri.parse('http://127.0.0.1:${server.port}/main.dart.js');
    final client = HttpClient()..autoUncompress = false;
    addTearDown(client.close);

    final identity = await client.getUrl(uri);
    identity.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final identityResponse = await identity.close();
    expect(identityResponse.statusCode, HttpStatus.ok);
    expect(identityResponse.contentLength, sourceBytes.length);
    expect(
      identityResponse.headers.value(HttpHeaders.contentEncodingHeader),
      isNull,
    );
    expect(
      identityResponse.headers.value(HttpHeaders.varyHeader),
      'Accept-Encoding',
    );
    expect(
      await identityResponse.fold<int>(0, (sum, chunk) => sum + chunk.length),
      sourceBytes.length,
    );
    final etag = identityResponse.headers.value(HttpHeaders.etagHeader);
    expect(etag, isNotNull);

    final compressed = await client.getUrl(uri);
    compressed.headers.set(
      HttpHeaders.acceptEncodingHeader,
      'br, gzip;q=0.8, identity;q=0.4',
    );
    final compressedResponse = await compressed.close();
    final compressedBytes = await compressedResponse.fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    expect(compressedResponse.statusCode, HttpStatus.ok);
    expect(
      compressedResponse.headers.value(HttpHeaders.contentEncodingHeader),
      'gzip',
    );
    expect(compressedResponse.contentLength, -1);
    expect(gzip.decode(compressedBytes), sourceBytes);
    expect(compressedBytes.length, lessThan(sourceBytes.length ~/ 4));

    final compressedHead = await client.openUrl('HEAD', uri);
    compressedHead.headers.set(
      HttpHeaders.acceptEncodingHeader,
      'gzip, identity;q=0.5',
    );
    final compressedHeadResponse = await compressedHead.close();
    expect(compressedHeadResponse.statusCode, HttpStatus.ok);
    expect(
      compressedHeadResponse.headers.value(HttpHeaders.contentEncodingHeader),
      'gzip',
    );
    expect(
      compressedHeadResponse.headers.value(HttpHeaders.varyHeader),
      'Accept-Encoding',
    );
    expect(await compressedHeadResponse.toList(), isEmpty);

    final compressedNotModified = await client.getUrl(uri);
    compressedNotModified.headers
      ..set(HttpHeaders.acceptEncodingHeader, 'gzip, identity;q=0.5')
      ..set(HttpHeaders.ifNoneMatchHeader, etag!);
    final compressedNotModifiedResponse = await compressedNotModified.close();
    expect(compressedNotModifiedResponse.statusCode, HttpStatus.notModified);
    expect(
      compressedNotModifiedResponse.headers.value(HttpHeaders.varyHeader),
      'Accept-Encoding',
    );
    expect(
      compressedNotModifiedResponse.headers.contentType?.mimeType,
      'text/javascript',
    );
    expect(
      compressedNotModifiedResponse.headers.value(
        HttpHeaders.contentEncodingHeader,
      ),
      'gzip',
    );
    expect(await compressedNotModifiedResponse.toList(), isEmpty);

    final disabled = await client.getUrl(uri);
    disabled.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip;q=0, *;q=1');
    final disabledResponse = await disabled.close();
    expect(disabledResponse.contentLength, sourceBytes.length);
    expect(
      disabledResponse.headers.value(HttpHeaders.contentEncodingHeader),
      isNull,
    );
    await disabledResponse.drain<void>();

    final identityPreferred = await client.getUrl(uri);
    identityPreferred.headers.set(
      HttpHeaders.acceptEncodingHeader,
      'gzip;q=0.1, identity;q=1',
    );
    final identityPreferredResponse = await identityPreferred.close();
    expect(identityPreferredResponse.statusCode, HttpStatus.ok);
    expect(identityPreferredResponse.contentLength, sourceBytes.length);
    expect(
      identityPreferredResponse.headers.value(
        HttpHeaders.contentEncodingHeader,
      ),
      isNull,
    );
    await identityPreferredResponse.drain<void>();

    for (final rejected in <String>['gzip;q=0, identity;q=0', '*;q=0']) {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptEncodingHeader, rejected);
      final response = await request.close();
      expect(response.statusCode, HttpStatus.notAcceptable, reason: rejected);
      expect(response.contentLength, 0, reason: rejected);
      expect(
        response.headers.value(HttpHeaders.varyHeader),
        'Accept-Encoding',
        reason: rejected,
      );
      expect(
        response.headers.value(HttpHeaders.cacheControlHeader),
        isNull,
        reason: rejected,
      );
      expect(
        response.headers.value(HttpHeaders.etagHeader),
        isNull,
        reason: rejected,
      );
      expect(
        response.headers.value(HttpHeaders.lastModifiedHeader),
        isNull,
        reason: rejected,
      );
      expect(await response.toList(), isEmpty, reason: rejected);
    }

    final compressionDisabledServer = await IoServer.bind(
      (_) async => ServerResponse.text('missing', status: HttpStatus.notFound),
      port: 0,
      publicDirectory: public,
      compressStaticAssets: false,
    );
    addTearDown(compressionDisabledServer.close);
    final explicitlyDisabled = await client.getUrl(
      Uri.parse(
        'http://127.0.0.1:${compressionDisabledServer.port}/main.dart.js',
      ),
    );
    explicitlyDisabled.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
    final explicitlyDisabledResponse = await explicitlyDisabled.close();
    expect(explicitlyDisabledResponse.contentLength, sourceBytes.length);
    expect(
      explicitlyDisabledResponse.headers.value(
        HttpHeaders.contentEncodingHeader,
      ),
      isNull,
    );
    expect(
      explicitlyDisabledResponse.headers.value(HttpHeaders.varyHeader),
      isNull,
    );
    await explicitlyDisabledResponse.drain<void>();

    final disabledNegotiation = await client.getUrl(
      Uri.parse(
        'http://127.0.0.1:${compressionDisabledServer.port}/main.dart.js',
      ),
    );
    disabledNegotiation.headers.set(HttpHeaders.acceptEncodingHeader, '*;q=0');
    final disabledNegotiationResponse = await disabledNegotiation.close();
    expect(disabledNegotiationResponse.statusCode, HttpStatus.ok);
    expect(disabledNegotiationResponse.contentLength, sourceBytes.length);
    expect(
      disabledNegotiationResponse.headers.value(HttpHeaders.varyHeader),
      isNull,
    );
    await disabledNegotiationResponse.drain<void>();
  });

  test(
    'IO adapter does not report successful responses as cancelled',
    () async {
      final normalCancellation = Completer<Future<void>>();
      final normalServer = await IoServer.bind((request) async {
        normalCancellation.complete(request.cancelled!);
        return ServerResponse.text('ok');
      }, port: 0);
      addTearDown(normalServer.close);
      final client = HttpClient();
      addTearDown(client.close);

      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${normalServer.port}/'),
      );
      final response = await request.close();
      expect(await response.transform(utf8.decoder).join(), 'ok');
      final completedNormally = await Future.any<bool>(<Future<bool>>[
        (await normalCancellation.future).then((_) => true),
        Future<bool>.delayed(const Duration(milliseconds: 50), () => false),
      ]);
      expect(completedNormally, isFalse);
    },
  );

  test(
    'IO adapter rejects unsupported methods before proxy or dispatch',
    () async {
      final proxyDirectory = await Directory.systemTemp.createTemp(
        'odroe-proxy-',
      );
      addTearDown(() => proxyDirectory.delete(recursive: true));
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));
      var proxied = false;
      upstream.listen((request) {
        proxied = true;
        unawaited(request.response.close());
      });
      final originFile = File('${proxyDirectory.path}/origin');
      await originFile.writeAsString('http://127.0.0.1:${upstream.port}');
      var dispatched = false;
      final server = await IoServer.bind(
        (_) async {
          dispatched = true;
          return ServerResponse.text('unexpected');
        },
        port: 0,
        developmentProxyOriginFile: originFile,
      );
      addTearDown(server.close);
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      addTearDown(socket.destroy);
      socket.add(
        utf8.encode(
          'FOO /\$test HTTP/1.1\r\n'
          'Host: 127.0.0.1:${server.port}\r\n'
          'Connection: close\r\n'
          'Content-Length: 0\r\n'
          '\r\n',
        ),
      );
      await socket.flush();

      final response = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      expect(response, startsWith('HTTP/1.1 501 Not Implemented'));
      expect(proxied, isFalse);
      expect(dispatched, isFalse);
    },
  );

  test(
    'IO adapter serves exact public files before development proxy',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'odroe-public-proxy-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await File('${directory.path}/vendor.js').writeAsString('public vendor');

      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));
      upstream.listen((request) {
        request.response.write('proxy ${request.uri.path}');
        unawaited(request.response.close());
      });
      final originFile = File('${directory.path}/origin');
      await originFile.writeAsString('http://127.0.0.1:${upstream.port}');

      final server = await IoServer.bind(
        (_) async => ServerResponse.text('dynamic'),
        port: 0,
        publicDirectory: directory,
        developmentProxyOriginFile: originFile,
      );
      addTearDown(server.close);
      final client = HttpClient();
      addTearDown(client.close);
      final base = Uri.parse('http://127.0.0.1:${server.port}');

      final public = await client.getUrl(base.resolve('/vendor.js'));
      final publicResponse = await public.close();
      expect(publicResponse.statusCode, HttpStatus.ok);
      expect(
        await publicResponse.transform(utf8.decoder).join(),
        'public vendor',
      );

      final proxied = await client.getUrl(base.resolve('/missing.js'));
      final proxiedResponse = await proxied.close();
      expect(proxiedResponse.statusCode, HttpStatus.ok);
      expect(
        await proxiedResponse.transform(utf8.decoder).join(),
        'proxy /missing.js',
      );
    },
  );

  test('IO adapter cancels a body omitted by HTTP semantics', () async {
    final cancelled = Completer<void>();
    final server = await IoServer.bind((request) async {
      Stream<List<int>> body() async* {
        try {
          yield <int>[1, 2, 3];
        } finally {
          cancelled.complete();
        }
      }

      return ServerResponse(body: body());
    }, port: 0);
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);

    final request = await client.openUrl(
      'HEAD',
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    await response.drain<void>();
    await cancelled.future.timeout(const Duration(seconds: 2));
  });

  test('IO adapter cancels a body when response metadata is invalid', () async {
    final cancelled = Completer<void>();
    final server = await IoServer.bind((request) async {
      Stream<List<int>> body() async* {
        try {
          yield <int>[1, 2, 3];
        } finally {
          cancelled.complete();
        }
      }

      return ServerResponse(
        headers: Headers()..set('invalid\nname', 'value'),
        body: body(),
      );
    }, port: 0);
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);

    final response = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    final received = await response.close();

    expect(received.statusCode, HttpStatus.internalServerError);
    await received.drain<void>();
    await cancelled.future.timeout(const Duration(seconds: 2));
  });
}
