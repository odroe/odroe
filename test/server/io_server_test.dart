import 'dart:async';
import 'dart:io';

import 'package:odroe/document.dart';
import 'package:odroe/router.dart';
import 'package:odroe/server_io.dart';
import 'package:test/test.dart';

void main() {
  test('IO adapter serves assets without escaping the public root', () async {
    final public = await Directory.systemTemp.createTemp('odroe-public-');
    final outside = await Directory.systemTemp.createTemp('odroe-private-');
    addTearDown(() => public.delete(recursive: true));
    addTearDown(() => outside.delete(recursive: true));
    await File('${public.path}/flutter_bootstrap.js').writeAsString('boot');
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
