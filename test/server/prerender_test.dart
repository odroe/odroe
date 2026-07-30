import 'dart:async';
import 'dart:io';

import 'package:odroe/document.dart';
import 'package:odroe/router.dart';
import 'package:odroe/server_io.dart';
import 'package:test/test.dart';

void main() {
  test('prerenderer rejects non-positive concurrency', () async {
    final output = await Directory.systemTemp.createTemp(
      'odroe-ssg-concurrency-',
    );
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
  });

  test('prerenderer times out while draining a redirect body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, '/target')
        ..write('redirecting');
      unawaited(request.response.flush().catchError((_) {}));
    });
    addTearDown(() => server.close(force: true));
    final output = await Directory.systemTemp.createTemp('odroe-ssg-redirect-');
    addTearDown(() => output.delete(recursive: true));

    await expectLater(
      () => Prerenderer().render(
        origin: Uri.parse('http://127.0.0.1:${server.port}'),
        routes: const <String>['/'],
        output: output,
        crawlLinks: false,
        timeout: const Duration(milliseconds: 100),
      ),
      throwsA(isA<TimeoutException>()),
    );
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
