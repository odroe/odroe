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
}
