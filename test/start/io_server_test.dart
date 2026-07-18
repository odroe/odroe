import 'dart:io';

import 'package:odroe/start_io.dart';
import 'package:test/test.dart';

void main() {
  test(
    'IO adapter serves Flutter assets without bypassing Start routes',
    () async {
      final public = await Directory.systemTemp.createTemp('odroe-public-');
      addTearDown(() => public.delete(recursive: true));
      await File('${public.path}/flutter_bootstrap.js').writeAsString('boot');
      final app = StartApplication(
        routes: <AnyAppRoute>[AppRoute<NoParams, NoSearch, NoData>(path: '/')],
      );
      final server = await StartIoServer.bind(
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
      expect(
        assetResponse.headers.value(HttpHeaders.cacheControlHeader),
        'no-cache',
      );

      final route = await client.getUrl(base.resolve('/'));
      route.headers.set(HttpHeaders.acceptHeader, 'text/html');
      final routeResponse = await route.close();
      expect(routeResponse.statusCode, HttpStatus.ok);
      expect(
        routeResponse.headers.contentType?.mimeType,
        ContentType.html.mimeType,
      );
    },
  );

  test('IO adapter does not follow public symlinks outside the root', () async {
    if (Platform.isWindows) return;
    final public = await Directory.systemTemp.createTemp('odroe-public-');
    final outside = await Directory.systemTemp.createTemp('odroe-private-');
    addTearDown(() => public.delete(recursive: true));
    addTearDown(() => outside.delete(recursive: true));
    await File('${outside.path}/secret.txt').writeAsString('secret');
    await Link(
      '${public.path}/secret.txt',
    ).create('${outside.path}/secret.txt');
    final app = StartApplication(
      routes: <AnyAppRoute>[AppRoute<NoParams, NoSearch, NoData>(path: '/')],
    );
    final server = await StartIoServer.bind(
      app.handle,
      port: 0,
      publicDirectory: public,
    );
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);

    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/secret.txt'),
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.notFound);
    expect(
      await response.transform(SystemEncoding().decoder).join(),
      isNot(contains('secret')),
    );
  });

  test(
    'IO adapter proxies Flutter DevFS assets without replacing pages',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));
      upstream.listen((request) async {
        if (request.uri.path.contains(r'$dwdsSseHandler')) {
          final body = await request
              .cast<List<int>>()
              .transform(SystemEncoding().decoder)
              .join();
          request.response.write('debug:$body');
          await request.response.close();
          return;
        }
        request.response
          ..headers.contentType = ContentType(
            'text',
            'javascript',
            charset: 'utf-8',
          )
          ..write('dev-bootstrap');
        await request.response.close();
      });
      final temporary = await Directory.systemTemp.createTemp('odroe-proxy-');
      addTearDown(() => temporary.delete(recursive: true));
      final originFile = File('${temporary.path}/origin')
        ..writeAsStringSync('http://127.0.0.1:${upstream.port}');
      final app = StartApplication(
        routes: <AnyAppRoute>[
          AppRoute<NoParams, NoSearch, NoData>(
            path: '/',
            document: (_) => const RouteDocument(title: 'Start page'),
          ),
        ],
      );
      final server = await StartIoServer.bind(
        app.handle,
        port: 0,
        developmentProxyOriginFile: originFile,
      );
      addTearDown(() => server.close(force: true));
      final client = HttpClient();
      addTearDown(client.close);
      final base = Uri.parse('http://127.0.0.1:${server.port}');

      final asset = await client.getUrl(base.resolve('/flutter_bootstrap.js'));
      final assetResponse = await asset.close();
      expect(
        await assetResponse.transform(SystemEncoding().decoder).join(),
        'dev-bootstrap',
      );

      final page = await client.getUrl(base.resolve('/'));
      page.headers.set(HttpHeaders.acceptHeader, 'text/html');
      final pageResponse = await page.close();
      final html = await pageResponse
          .transform(SystemEncoding().decoder)
          .join();
      expect(html, contains('<title>Start page</title>'));
      expect(html, isNot(contains('dev-bootstrap')));

      final debug = await client.postUrl(
        base.resolve(r'/token/$dwdsSseHandler'),
      );
      debug.write('ping');
      final debugResponse = await debug.close();
      expect(
        await debugResponse.transform(SystemEncoding().decoder).join(),
        'debug:ping',
      );
    },
  );
}
