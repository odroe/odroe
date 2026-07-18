import 'package:odroe/start.dart';
import 'package:test/test.dart';

void main() {
  test('route documents merge head and compose semantic bodies', () async {
    late final AppRoute<NoParams, NoSearch, NoData> parent;
    final child = AppRoute<NoParams, NoSearch, String>(
      path: 'post',
      load: (_) => '<Odroe>',
      document: (context) {
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
      },
    );
    parent = AppRoute<NoParams, NoSearch, NoData>(
      path: '/',
      terminal: false,
      document: (_) => const RouteDocument(
        language: 'en',
        baseHref: '/docs/',
        title: 'Parent',
        description: 'Parent description',
        body: HtmlElement('main', children: <HtmlNode>[HtmlOutlet()]),
      ),
      children: <AnyAppRoute>[child],
    );
    final app = StartApplication(routes: <AnyAppRoute>[parent]);

    final response = await app.handle(
      StartRequest.bytes(
        method: StartMethod.get,
        uri: Uri.parse('http://localhost/post'),
        headers: StartHeaders.single(<String, String>{'accept': 'text/html'}),
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

  test('a parent body without an outlet rejects descendant content', () {
    expect(
      () => resolveDocument(const <RouteDocument>[
        RouteDocument(body: HtmlElement('main')),
        RouteDocument(body: HtmlElement('article')),
      ]),
      throwsStateError,
    );
  });

  test('renderer rejects invalid tags and children on void elements', () {
    expect(
      () => renderDocumentStart(
        resolveDocument(const <RouteDocument>[
          RouteDocument(body: HtmlElement('script>alert(1)')),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => renderDocumentStart(
        resolveDocument(const <RouteDocument>[
          RouteDocument(
            body: HtmlElement('img', children: <HtmlNode>[HtmlText('bad')]),
          ),
        ]),
      ),
      throwsStateError,
    );
  });
}
