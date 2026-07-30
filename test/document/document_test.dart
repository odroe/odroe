import 'package:odroe/document.dart';
import 'package:odroe/odroe.dart';
import 'package:odroe/router.dart';
import 'package:odroe/server.dart';
import 'package:test/test.dart';

const _greetingKey = ContextKey<String>('greeting');

final class _GreetingModule extends Module {
  const _GreetingModule();

  @override
  void register(ModuleRegistry registry) {
    registry.provide(_greetingKey, 'Hello');
  }
}

final class _OpaqueData {
  const _OpaqueData(this.name);

  final String name;
}

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
    expect(response.headers.value('vary'), 'Accept');
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

  test('pure HTML reads modules without serializing loader data', () async {
    final route = AppRoute<NoParams, NoSearch, _OpaqueData>(path: '/')
        .document(
          (context) => RouteDocument(
            title: '${context.read(_greetingKey)} ${context.data.name}',
          ),
        )
        .server(load: (_) => const _OpaqueData('Odroe'));
    final app = Server(
      routes: <RouteNode>[route],
      modules: () => const <Module>[_GreetingModule()],
      renderer: const DocumentRenderer().call,
    );

    final response = await app.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: Headers.single(<String, String>{'accept': 'text/html'}),
      ),
    );
    final html = await response.readText();

    expect(response.status, 200);
    expect(html, contains('<title>Hello Odroe</title>'));
    expect(html, isNot(contains('__odroe_state__')));
    expect(html, isNot(contains('flutter_bootstrap.js')));
  });

  test('document responses honor media quality and wildcards', () async {
    final route = AppRoute<NoParams, NoSearch, NoData>(
      path: '/',
    ).document((_) => const RouteDocument(title: 'Negotiated'));
    final app = Server(
      routes: <RouteNode>[route],
      renderer: const DocumentRenderer().call,
    );

    Future<ServerResponse> request(String accept) => app.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: Headers.single(<String, String>{'accept': accept}),
      ),
    );

    final json = await request('application/json;q=0.9, text/html;q=0.1');
    expect(json.headers.value('content-type'), contains('application/json'));
    await json.readText();

    final textWildcard = await request('application/json;q=0.4, text/*;q=0.5');
    expect(textWildcard.headers.value('content-type'), contains('text/html'));
    await textWildcard.readText();

    final any = await request('*/*');
    expect(any.headers.value('content-type'), contains('text/html'));
    await any.readText();
  });

  test('dynamic HTML and JSON failures vary by Accept', () async {
    final route = AppRoute<NoParams, NoSearch, NoData>(
      path: '/',
    ).document((_) => const RouteDocument(title: 'Home'));
    final app = Server(
      routes: <RouteNode>[route],
      renderer: const DocumentRenderer().call,
    );

    Future<ServerResponse> request(String accept) => app.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/missing'),
        headers: Headers.single(<String, String>{'accept': accept}),
      ),
    );

    final html = await request('text/html');
    expect(html.status, 404);
    expect(html.headers.value('content-type'), contains('text/html'));
    expect(html.headers.value('vary'), 'Accept');
    expect(await html.readText(), contains('<title>Page not found</title>'));

    final json = await request('application/json;q=0.9, text/html;q=0.1');
    expect(json.status, 404);
    expect(json.headers.value('content-type'), contains('application/json'));
    expect(json.headers.value('vary'), 'Accept');
    expect(await json.readText(), contains('"type":"notFound"'));
  });
}
