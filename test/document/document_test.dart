import 'package:odroe/document.dart';
import 'package:odroe/router.dart';
import 'package:odroe/server.dart';
import 'package:test/test.dart';

void main() {
  test('route documents merge head and compose semantic bodies', () async {
    late final AppRoute<NoParams, NoSearch, NoData> parent;
    final child = AppRoute<NoParams, NoSearch, String>(path: 'post')
        .document((context) {
          expect(context.match(parent)?.data, const NoData());
          return RouteDocument(
            title: 'Child',
            description: 'Child description',
            canonical: '/post',
            meta: const <DocumentMeta>[
              DocumentMeta.property('og:title', 'Child'),
            ],
            jsonLd: const <Object?>[
              <String, Object?>{'@type': 'Article'},
            ],
            body: HtmlElement(
              'article',
              children: <HtmlNode>[
                HtmlElement('h1', children: <HtmlNode>[HtmlText(context.data)]),
              ],
            ),
          );
        })
        .server(load: (_) => '<Odroe>');
    parent =
        AppRoute<NoParams, NoSearch, NoData>(
          path: '/',
          terminal: false,
          children: <RouteNode>[child],
        ).document(
          (_) => const RouteDocument(
            language: 'en',
            baseHref: '/docs/',
            title: 'Parent',
            description: 'Parent description',
            body: HtmlElement('main', children: <HtmlNode>[HtmlOutlet()]),
          ),
        );
    final app = Server(
      routes: <RouteNode>[parent],
      renderer: const DocumentRenderer().call,
    );

    final response = await app.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/post'),
        headers: Headers.single(<String, String>{'accept': 'text/html'}),
      ),
    );
    final html = await response.readText();

    expect(response.headers.value('content-type'), contains('text/html'));
    expect(html, contains('<html lang="en">'));
    expect(html, contains('<base href="/docs/">'));
    expect(html, contains('<title>Child</title>'));
    expect(
      html,
      contains('<meta name="description" content="Child description">'),
    );
    expect(html, contains('<link rel="canonical" href="/post">'));
    expect(html, contains('<script type="application/ld+json">'));
    expect(
      html,
      contains('<main><article><h1>&lt;Odroe&gt;</h1></article></main>'),
    );
    expect(html, isNot(contains('__odroe_state__')));
    expect(html, isNot(contains('flutter_bootstrap.js')));
  });
}
