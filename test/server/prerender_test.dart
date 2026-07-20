import 'dart:io';

import 'package:odroe/document.dart';
import 'package:odroe/router.dart';
import 'package:odroe/server_io.dart';
import 'package:test/test.dart';

void main() {
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
    final root =
        AppRoute<NoParams, NoSearch, NoData>(
          path: '/',
          children: <RouteNode>[
            AppRoute<NoParams, NoSearch, NoData>(
              path: 'posts',
              terminal: false,
              children: <RouteNode>[post],
            ),
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
  });
}
