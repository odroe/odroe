import 'dart:async';
import 'dart:io';

import 'package:odroe/document.dart';
import 'package:odroe/router.dart';
import 'package:odroe/server_io.dart';
import 'package:test/test.dart';

void main() {
  test('prerenderer rejects non-positive resource limits', () async {
    final output = await Directory.systemTemp.createTemp('odroe-ssg-limits-');
    addTearDown(() => output.delete(recursive: true));

    for (final concurrency in <int>[0, -1]) {
      await expectLater(
        () => Prerenderer().render(
          origin: Uri.parse('http://127.0.0.1:1'),
          routes: const <String>['/'],
          output: output,
          concurrency: concurrency,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.invalidValue,
            'invalidValue',
            concurrency,
          ),
        ),
      );
    }
    for (final maxRoutes in <int>[0, -1]) {
      await expectLater(
        () => Prerenderer().render(
          origin: Uri.parse('http://127.0.0.1:1'),
          routes: const <String>['/'],
          output: output,
          maxRoutes: maxRoutes,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.invalidValue,
            'invalidValue',
            maxRoutes,
          ),
        ),
      );
    }
    for (final maxResponseBytes in <int>[0, -1]) {
      await expectLater(
        () => Prerenderer().render(
          origin: Uri.parse('http://127.0.0.1:1'),
          routes: const <String>['/'],
          output: output,
          maxResponseBytes: maxResponseBytes,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.invalidValue,
            'invalidValue',
            maxResponseBytes,
          ),
        ),
      );
    }

    await expectLater(
      () => Prerenderer().render(
        origin: Uri.parse('http://127.0.0.1:1'),
        routes: const <String>['/one', '/two'],
        output: output,
        maxRoutes: 1,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Prerender route limit of 1 exceeded'),
        ),
      ),
    );

    for (final route in const <String>[
      'docs',
      'https://example.com/docs',
      '/docs?draft=true',
      '/docs#intro',
    ]) {
      await expectLater(
        () => Prerenderer().render(
          origin: Uri.parse('http://127.0.0.1:1'),
          routes: <String>[route],
          output: output,
        ),
        throwsArgumentError,
        reason: route,
      );
    }
  });

  test('prerenderer does not wait for redirect bodies', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      if (request.uri.path == '/target') {
        request.response
          ..headers.contentType = ContentType.html
          ..write('<!doctype html><title>target</title>');
        unawaited(request.response.close());
        return;
      }
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, '/target')
        ..write('redirecting');
      unawaited(request.response.flush().catchError((_) {}));
    });
    addTearDown(() => server.close(force: true));
    final output = await Directory.systemTemp.createTemp('odroe-ssg-redirect-');
    addTearDown(() => output.delete(recursive: true));

    final rendered = await Prerenderer()
        .render(
          origin: Uri.parse('http://127.0.0.1:${server.port}'),
          routes: const <String>['/'],
          output: output,
          timeout: const Duration(milliseconds: 100),
        )
        .timeout(const Duration(seconds: 1));

    expect(rendered.map((route) => route.route), <String>['/', '/target']);
  });

  test('response timeout releases a caller-owned client', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      if (request.uri.path == '/headers-stalled') return;
      request.response.headers.contentType = ContentType.html;
      if (request.uri.path == '/body-stalled') {
        request.response.write('<!doctype html><title>stalled');
        unawaited(request.response.flush().catchError((_) {}));
        return;
      }
      request.response.write('<!doctype html><title>ok</title>');
      unawaited(request.response.close());
    });
    addTearDown(() => server.close(force: true));
    final client = HttpClient()..maxConnectionsPerHost = 1;
    addTearDown(() => client.close(force: true));
    final output = await Directory.systemTemp.createTemp('odroe-ssg-cancel-');
    addTearDown(() => output.delete(recursive: true));
    final prerenderer = Prerenderer(client: client);
    final origin = Uri.parse('http://127.0.0.1:${server.port}');

    for (final route in const <String>['/body-stalled', '/headers-stalled']) {
      await expectLater(
        prerenderer.render(
          origin: origin,
          routes: <String>[route],
          output: Directory('${output.path}${route.replaceAll('-', '_')}'),
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<TimeoutException>()),
        reason: route,
      );
    }

    final rendered = await prerenderer
        .render(
          origin: origin,
          routes: const <String>['/ok'],
          output: Directory('${output.path}/ok'),
        )
        .timeout(const Duration(seconds: 1));
    expect(rendered.single.route, '/ok');
  });

  test('prerenderer bounds redirect chains and response bytes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      response.headers.contentType = ContentType.html;
      switch (request.uri.path) {
        case '/redirect-1':
          response
            ..statusCode = HttpStatus.temporaryRedirect
            ..headers.set(HttpHeaders.locationHeader, '/redirect-2');
        case '/redirect-2':
          response
            ..statusCode = HttpStatus.temporaryRedirect
            ..headers.set(HttpHeaders.locationHeader, '/redirect-3');
        case '/declared':
          response
            ..contentLength = 64
            ..add(List<int>.filled(64, 65));
        case '/streamed':
          response
            ..bufferOutput = false
            ..add(List<int>.filled(24, 65));
          await response.flush();
          response.add(List<int>.filled(24, 66));
        default:
          response.write('<!doctype html><title>ok</title>');
      }
      await response.close();
    });
    addTearDown(() => server.close(force: true));
    final origin = Uri.parse('http://127.0.0.1:${server.port}');
    final output = await Directory.systemTemp.createTemp('odroe-ssg-bounds-');
    addTearDown(() => output.delete(recursive: true));

    await expectLater(
      Prerenderer().render(
        origin: origin,
        routes: const <String>['/redirect-1'],
        output: output,
        maxRoutes: 2,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Prerender route limit of 2 exceeded'),
        ),
      ),
    );

    for (final route in const <String>['/declared', '/streamed']) {
      final routeOutput = Directory(
        '${output.path}/${route.substring(1)}-output',
      );
      await expectLater(
        Prerenderer().render(
          origin: origin,
          routes: <String>[route],
          output: routeOutput,
          maxResponseBytes: 32,
        ),
        throwsA(
          isA<HttpException>().having(
            (error) => error.message,
            'message',
            contains('exceeds the 32 byte prerender limit'),
          ),
        ),
        reason: route,
      );
      expect(
        File('${routeOutput.path}$route/index.html').existsSync(),
        isFalse,
        reason: route,
      );
    }
  });

  test('prerenderer never exceeds requested concurrency', () async {
    var active = 0;
    var peak = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      active++;
      if (active > peak) peak = active;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      request.response
        ..headers.contentType = ContentType.html
        ..write('<!doctype html><title>${request.uri.path}</title>');
      await request.response.close();
      active--;
    });
    addTearDown(() => server.close(force: true));
    final output = await Directory.systemTemp.createTemp(
      'odroe-ssg-parallelism-',
    );
    addTearDown(() => output.delete(recursive: true));

    final rendered = await Prerenderer().render(
      origin: Uri.parse('http://127.0.0.1:${server.port}'),
      routes: <String>[for (var index = 0; index < 6; index++) '/$index'],
      output: output,
      concurrency: 2,
    );

    expect(rendered, hasLength(6));
    expect(peak, 2);
  });

  test('prerenderer fetches the real app and crawls local links', () async {
    final post =
        AppRoute<({int id}), NoSearch, NoData>(
          path: ':id',
          params: PathParams<({int id})>.codec(
            decode: (input) => (id: input.requiredInt('id')),
            encode: (value, output) => output.integer('id', value.id),
          ),
        ).document(
          (context) => RouteDocument(
            title: 'Post ${context.params.id}',
            body: HtmlElement(
              'article',
              children: <HtmlNode>[
                HtmlElement(
                  'h1',
                  children: <HtmlNode>[HtmlText('Post ${context.params.id}')],
                ),
              ],
            ),
          ),
        );
    final versionedDocs = AppRoute<NoParams, NoSearch, NoData>(path: 'docs.v1')
        .document(
          (_) => const RouteDocument(
            title: 'Versioned docs',
            body: HtmlElement('h1', children: <HtmlNode>[HtmlText('Docs v1')]),
          ),
        );
    final root =
        AppRoute<NoParams, NoSearch, NoData>(
          path: '/',
          children: <RouteNode>[
            AppRoute<NoParams, NoSearch, NoData>(
              path: 'posts',
              terminal: false,
              children: <RouteNode>[post],
            ),
            versionedDocs,
          ],
        ).document(
          (_) => const RouteDocument(
            title: 'Home',
            body: HtmlElement(
              'main',
              children: <HtmlNode>[
                HtmlElement(
                  'a',
                  attributes: <String, String?>{'href': '/posts/42'},
                  children: <HtmlNode>[HtmlText('Post 42')],
                ),
                HtmlElement(
                  'a',
                  attributes: <String, String?>{'href': '/guide.pdf'},
                  children: <HtmlNode>[HtmlText('Guide PDF')],
                ),
                HtmlOutlet(),
              ],
            ),
          ),
        );
    final server = await IoServer.bind(
      Server(
        routes: <RouteNode>[root],
        renderer: const DocumentRenderer().call,
      ).handler,
      port: 0,
    );
    addTearDown(() => server.close(force: true));
    final output = await Directory.systemTemp.createTemp('odroe-ssg-');
    addTearDown(() => output.delete(recursive: true));

    final prerenderer = Prerenderer();
    final result = await prerenderer.render(
      origin: Uri.parse('http://127.0.0.1:${server.port}'),
      routes: const <String>['/'],
      output: output,
      concurrency: 2,
      crawlLinks: true,
    );

    expect(result.map((route) => route.route), <String>['/', '/posts/42']);
    expect(
      await File('${output.path}/index.html').readAsString(),
      contains('Home'),
    );
    expect(
      await File('${output.path}/posts/42/index.html').readAsString(),
      contains('Post 42'),
    );

    final explicitOnly = await prerenderer.render(
      origin: Uri.parse('http://127.0.0.1:${server.port}'),
      routes: const <String>['/'],
      output: Directory('${output.path}/explicit'),
    );
    expect(explicitOnly.map((route) => route.route), const <String>['/']);

    await expectLater(
      prerenderer.render(
        origin: Uri.parse('http://127.0.0.1:${server.port}'),
        routes: const <String>['/'],
        output: Directory('${output.path}/route-limit'),
        crawlLinks: true,
        maxRoutes: 1,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Prerender route limit of 1 exceeded'),
        ),
      ),
    );

    final repeated = await prerenderer.render(
      origin: Uri.parse('http://127.0.0.1:${server.port}'),
      routes: const <String>['/posts/42'],
      output: output,
    );
    expect(repeated.single.route, '/posts/42');

    final dotted = await prerenderer.render(
      origin: Uri.parse('http://127.0.0.1:${server.port}'),
      routes: const <String>['/docs.v1'],
      output: output,
      crawlLinks: false,
    );
    expect(dotted.single.route, '/docs.v1');
    expect(
      await File('${output.path}/docs.v1/index.html').readAsString(),
      contains('Docs v1'),
    );

    await expectLater(
      prerenderer.render(
        origin: Uri.parse('http://127.0.0.1:${server.port}'),
        routes: const <String>['/posts/42', '/posts/42/index.html'],
        output: output,
        concurrency: 2,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('both write "posts/42/index.html"'),
        ),
      ),
    );
  });
}
