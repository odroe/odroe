import 'dart:convert';
import 'dart:io';

import 'package:odroe/document.dart';
import 'package:odroe/query.dart';
import 'package:odroe/server.dart';
import 'package:odroe_dev/content.dart';
import 'package:odroe_dev/routes.server.dart' as generated;
import 'package:test/test.dart';

void main() {
  test('every published location renders semantic HTML', () async {
    final server = Server(
      routes: generated.serverRouteTree,
      functions: generated.serverFunctions,
      renderer: const DocumentRenderer(baseHref: '/').call,
      exposeErrors: true,
    );
    final locations = <Uri>[
      Uri(path: '/'),
      Uri(path: '/404.html'),
      ...await docs.locations(),
    ];

    for (final location in locations) {
      final response = await server.handle(
        ServerRequest(
          method: HttpMethod.get,
          uri: location,
          headers: Headers.single(<String, String>{'accept': 'text/html'}),
        ),
      );
      final body = await utf8.decodeStream(response.body);

      expect(response.status, 200, reason: '${location.path}\n$body');
      expect(body, startsWith('<!doctype html>'));
      expect(body, contains('<main id="main-content">'));
      if (location.path == '/404.html') {
        expect(_canonical.allMatches(body), isEmpty);
        expect(_meta(body, 'og:url'), isEmpty);
      } else {
        final title = _single(_title.allMatches(body), location, 'title');
        final canonical = _single(
          _canonical.allMatches(body),
          location,
          'canonical',
        );
        final ogTitle = _single(_meta(body, 'og:title'), location, 'og:title');
        final ogUrl = _single(_meta(body, 'og:url'), location, 'og:url');
        final ogImage = _single(_meta(body, 'og:image'), location, 'og:image');
        final ogImageAlt = _single(
          _meta(body, 'og:image:alt'),
          location,
          'og:image:alt',
        );
        final ogImageType = _single(
          _meta(body, 'og:image:type'),
          location,
          'og:image:type',
        );
        final ogImageWidth = _single(
          _meta(body, 'og:image:width'),
          location,
          'og:image:width',
        );
        final ogImageHeight = _single(
          _meta(body, 'og:image:height'),
          location,
          'og:image:height',
        );
        final expectedCanonical = Uri.parse(
          'https://odroe.dev',
        ).resolveUri(location).toString();

        expect(ogTitle, title, reason: location.path);
        expect(canonical, expectedCanonical, reason: location.path);
        expect(ogUrl, canonical, reason: location.path);
        expect(
          ogImage,
          'https://odroe.dev/social-card.png',
          reason: location.path,
        );
        expect(ogImageType, 'image/png', reason: location.path);
        expect(ogImageWidth, '1200', reason: location.path);
        expect(ogImageHeight, '630', reason: location.path);
        expect(
          ogImageAlt,
          'Odroe: One Dart package. Every layer — Flutter, Semantic Web, '
          'Typed Server, Data, and Cloudflare Preview.',
          reason: location.path,
        );
      }
      expect(body, isNot(contains('flutter_bootstrap.js')));
    }
  });

  test(
    'homepage structured data describes source without invented commerce',
    () async {
      final server = Server(
        routes: generated.serverRouteTree,
        functions: generated.serverFunctions,
        renderer: const DocumentRenderer(baseHref: '/').call,
      );
      final response = await server.handle(
        ServerRequest(
          method: HttpMethod.get,
          uri: Uri(path: '/'),
          headers: Headers.single(<String, String>{'accept': 'text/html'}),
        ),
      );
      final body = await utf8.decodeStream(response.body);

      expect(body, contains('"@type":"SoftwareSourceCode"'));
      expect(body, contains('"programmingLanguage":"Dart"'));
      expect(body, isNot(contains('"runtimePlatform":"Flutter"')));
      expect(body, isNot(contains('"@type":"SoftwareApplication"')));
      expect(body, isNot(contains('"aggregateRating"')));
      expect(body, isNot(contains('"offers"')));
      expect(body, contains('builder: (app) =&gt;'));
      expect(body, contains('Source preview'));
      expect(body, contains('Cloudflare preview'));
      expect(body, contains('Cloudflare Preview'));
      expect(body, contains('Verified locally'));
      expect(body, contains('explicitly choose a Flutter target'));
      expect(body, isNot(contains('Write the product once')));
      expect(body, isNot(contains('each runtime')));
      expect(body, isNot(contains('data models consistent')));
      expect(body, isNot(contains('Use only what you import')));
    },
  );

  test('social card is a 1200x630 PNG', () async {
    final bytes = await File('public/social-card.png').readAsBytes();
    final source = await File('public/social-card.svg').readAsString();

    expect(bytes.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    expect(_uint32(bytes, 16), 1200);
    expect(_uint32(bytes, 20), 630);
    expect(source, contains('Data · Cloudflare Preview'));
    expect(source, isNot(contains('Data · Edge')));
  });

  test('getting started closes the Flutter and Document run paths', () async {
    final source = await File(
      'content/docs/getting-started.mdc',
    ).readAsString();

    expect(source, contains('flutter create --platforms=android,ios,web'));
    expect(source, contains('lib/routes/route.dart'));
    expect(source, contains('lib/routes/page.dart'));
    expect(source, contains('MaterialApp.router'));
    expect(source, contains('dart run odroe dev --server-only'));
    expect(source, contains('flutter devices'));
    expect(source, contains('dart run odroe dev -- -d <ios-device-id>'));
    expect(source, isNot(contains('dart run odroe dev -- -d ios')));
    expect(source, contains('never reuses stale `build/web` HTML'));
  });

  test('runtime matrix reports Flutter evidence honestly', () async {
    final source = await File('content/docs/index.mdc').readAsString();

    expect(
      source,
      contains(
        '| Flutter Android, iOS, and Web | Flutter build | Verified locally | '
        'Example source builds Web, Android release APK, and unsigned iOS '
        'release in generated host scaffolds; no signed or device release '
        'claim |',
      ),
    );
    expect(
      source,
      isNot(
        contains(
          '| Flutter Android, iOS, and Web | Flutter build | Available |',
        ),
      ),
    );
  });

  test('extension key docs require one shared identity', () async {
    final app = (await File(
      'content/docs/core/app.mdc',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');
    final routing = (await File(
      'content/docs/core/routing.mdc',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');
    final server = (await File(
      'content/docs/server.mdc',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');

    expect(app, contains("final sessionKey = ContextKey<Session>('session');"));
    expect(app, contains('matched by instance identity'));
    expect(app, contains('reuse that exact instance'));
    expect(app, contains('sessionKey.provide(registry, session)'));
    expect(app, contains('context.read(sessionKey)'));
    expect(app, contains('replaces the old `const ContextKey(...)` form'));
    expect(app, contains('sessionKey.provideFactory(registry, createSession)'));
    expect(routing, contains('Capability keys also use instance identity'));
    expect(routing, contains('name is only diagnostic'));
    expect(routing, contains('Replace old `const RouteCapability(...)`'));
    expect(routing, contains('capability.attach(route, value)'));
    expect(
      server,
      contains("final userKey = RequestKey<User>('authenticated-user');"),
    );
    expect(server, contains('`RequestKey` uses instance identity'));
    expect(server, contains('reuse that exact instance'));
    expect(server, contains('Replace old `const RequestKey(...)`'));
    expect(server, contains('userKey.set(context, user)'));
    expect(server, contains('`key.set(context, value)`'));
    expect(server, isNot(contains('context.set(userKey, user)')));
    expect(app, isNot(contains('const sessionKey = ContextKey')));
  });

  test('unknown routes return a real 404 document', () async {
    final server = Server(
      routes: generated.serverRouteTree,
      functions: generated.serverFunctions,
      renderer: const DocumentRenderer(baseHref: '/').call,
    );
    final response = await server.handle(
      ServerRequest(
        method: HttpMethod.get,
        uri: Uri(path: '/missing'),
        headers: Headers.single(<String, String>{'accept': 'text/html'}),
      ),
    );

    expect(response.status, 404);
    final body = await utf8.decodeStream(response.body);
    expect(body, contains('Page not found'));
    expect(_canonical.allMatches(body), isEmpty);
    expect(_meta(body, 'og:url'), isEmpty);
  });

  test(
    'website deployment preserves canonical URLs and its static 404',
    () async {
      final config =
          jsonDecode(await File('wrangler.jsonc').readAsString())
              as Map<String, Object?>;
      final assets = config['assets']! as Map<String, Object?>;

      expect(assets['html_handling'], 'drop-trailing-slash');
      expect(assets['not_found_handling'], '404-page');
    },
  );

  test('Query docs match key and mutation lifecycle contracts', () async {
    final source = (await File(
      'content/docs/core/query.mdc',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');

    final options = QueryOptions<int>(
      key: QueryKey('post', <Object?>[42]),
      query: (_) async => 42,
    );
    expect(options.key, QueryKey('post', <Object?>[42]));
    expect(source, contains("key: QueryKey('post', <Object?>[postId]),"));
    expect(source, isNot(contains("QueryKey(<Object?>['post', postId])")));
    expect(
      source,
      contains(
        'Queries and infinite queries participate in `QueryClient` '
        'cancellation and invalidation.',
      ),
    );
    expect(
      source,
      contains(
        'Mutations keep separate cache, observer, scope, and retry '
        'lifecycles; use mutation callbacks to invalidate related queries '
        'explicitly.',
      ),
    );
    expect(
      source,
      isNot(
        contains('Queries, infinite queries, and mutations share cancellation'),
      ),
    );
    expect(
      source,
      contains(
        'cancelled: context.cancelToken.whenCancelled.then<void>((_) {})',
      ),
    );
    expect(source, contains('removal of the last observer'));
    expect(source, contains('Query keeps cancellation out of error state'));
    expect(source, contains('completed and pending Query data'));
    expect(source, contains("through the `Server`'s `Serializer`"));
    expect(source, contains('`DocumentModule` uses its serializer'));
    expect(source, contains('`DateTime`, `Duration`, `Uri`'));
    expect(source, contains('equivalent adapter sets'));
    expect(
      source,
      contains(
        'modules: () => <QueryClientModule>[QueryClientModule.server()]',
      ),
    );
    expect(source, contains('RpcModule.http(serializer: serializer)'));
    expect(source, contains('DocumentModule(serializer: serializer)'));
  });

  test('Database docs preserve the typed dialect boundary', () async {
    final source = (await File(
      'content/docs/data/database.mdc',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');

    expect(source, contains('preserves its selected dialect'));
    expect(source, contains('SQLite and D1 accept `SqlDialect.sqlite`'));
    expect(source, contains('PostgreSQL accepts `SqlDialect.postgres`'));
    expect(source, contains('MySQL/MariaDB accepts `SqlDialect.mysql`'));
    expect(source, contains('`SqlErrorCode.unsupported`'));
    expect(source, contains('before that statement reaches the database'));
    expect(source, contains('dialect: SqlDialect.postgres'));
    expect(source, contains('default to `dialect: null`'));
    expect(source, contains('does not prove that the SQL is portable'));
  });

  test('Server docs close the authenticated RPC contract', () async {
    final source = await File('content/docs/server.mdc').readAsString();
    final appSource = await File('content/docs/core/app.mdc').readAsString();

    expect(source, isNot(contains('SessionModule')));
    expect(appSource, isNot(contains('SessionModule')));
    expect(appSource, contains('QueryClientModule()'));
    expect(appSource, contains('context.read(queryClientKey)'));
    expect(source, contains('headersProvider: () async'));
    expect(source, contains("'authorization': 'Bearer \$token'"));
    expect(source, contains('middleware: <Middleware>[requireBearer]'));
    expect(source, contains("throw const HttpError(401, 'Sign in required.')"));
    expect(source, contains('context.request.require(userKey)'));
    expect(source, contains('app.read(rpcClientKey)'));
    expect(source, contains('RemoteServerException'));
    expect(source, contains('error.status == 401'));
    expect(source, contains('runs exactly once for each RPC request'));
    expect(source, contains('does not automatically retry'));
    expect(source, contains('RpcCancelledException'));
    expect(source, contains('ServerRequest.cancelled'));
    expect(
      source,
      contains('Future<void>.delayed(const Duration(seconds: 10))'),
    );
    expect(source, contains('Aborting a POST does not roll back'));
    expect(source, contains('Browser RPC is same-origin only'));
    expect(source, contains('Omit `baseUri` on Web'));
    expect(source, contains('Android, iOS, and desktop apps'));
    expect(source, contains('ODROE_API_ORIGIN'));
    expect(source, contains('A pre-cancelled call does not start'));
    expect(source, contains('upstream subscription'));
    expect(
      source,
      isNot(contains('request cancellation stay visible in the transport')),
    );
  });

  test('Server docs define bounded typed RPC frames', () async {
    final source = (await File(
      'content/docs/server.mdc',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');

    expect(source, contains('`Server.maxFunctionPayload`'));
    expect(source, contains('four independent byte boundaries'));
    expect(source, contains('`Server.maxFunctionResponseFrameBytes`'));
    expect(source, contains('defaults to 1 MiB'));
    expect(source, contains('minimum is 16 bytes'));
    expect(source, contains('`HttpTransport.maxRequestBodyBytes`'));
    expect(source, contains('PayloadTooLargeException'));
    expect(source, contains('does not cover GET query parameters'));
    expect(source, contains('Overflow returns HTTP 413'));
    expect(source, contains('This exception is local'));
    expect(source, contains('`RpcClient.maxResponseFrameBytes`'));
    expect(source, contains('maxRequestBodyBytes: 2 * 1024 * 1024'));
    expect(source, contains('maxResponseFrameBytes: 2 * 1024 * 1024'));
    expect(source, contains('before UTF-8 decoding'));
    expect(source, contains('cumulative stream size is not capped'));
    expect(source, contains('cancels the response body'));
    expect(source, contains('explicitly typed to return `ServerResponse`'));
    expect(source, contains('`Serializer.encode` still materializes'));
    expect(
      source,
      isNot(
        contains(
          'Payload limits and streaming frames remain explicit at the '
          'server and transport boundaries',
        ),
      ),
    );
  });

  test('Server docs define unexpected error reporting', () async {
    final document = await File('content/docs/server.mdc').readAsString();
    final firstDartBlock = RegExp(
      r'```dart\s+([\s\S]*?)\s+```',
    ).firstMatch(document)!.group(1)!;
    final source = document.replaceAll(RegExp(r'\s+'), ' ');

    expect(firstDartBlock, contains("import 'package:odroe/server.dart';"));
    expect(
      firstDartBlock,
      contains("import 'routes.server.dart' as generated;"),
    );
    expect(source, contains('through `Server.onError`'));
    expect(source, contains('default reporter writes'));
    expect(source, contains('current Dart `Zone`'));
    expect(source, contains('onError: (request, error, stackTrace)'));
    expect(source, contains('module setup failure is reported and rethrown'));
    expect(source, contains('return a bounded `Future`'));
    expect(source, contains('invokes it inline'));
    expect(source, contains('response close attempt settles'));
    expect(source, contains('same `ServerRequest`'));
    expect(source, contains('not query, headers, or body'));
    expect(source, contains('error and stack trace are written verbatim'));
    expect(source, contains('must not put sensitive data in exceptions'));
    expect(source, contains('generated native bootstrap creates one `Server`'));
    expect(source, contains('generated Fetch bootstrap also creates one'));
    expect(source, contains('response-byte conversion failures'));
    expect(source, contains('registered with the host `waitUntil`'));
    expect(source, contains('adapter-owned static files'));
    expect(source, contains('HTTP framing'));
    expect(source, contains('metadata-only diagnostic `ServerRequest`'));
    expect(
      source,
      contains('For a supported method, malformed forwarded authority'),
    );
    expect(source, contains('rejected with a controlled `400`'));
    expect(source, contains('not reported twice'));
    expect(source, contains('`HttpServer.close` does not await'));
    expect(source, contains('controlled HTTP 400 before the handler starts'));
    expect(source, contains('do not trigger `Server.onError`'));
    expect(source, contains('before a response starts'));
    expect(source, contains('except typed-frame overflow'));
    expect(source, contains('`exposeErrors` only controls client disclosure'));
    expect(source, contains('failing reporter cannot replace the original'));
    expect(source, contains('`ServerInvocation.onError` is the separate'));
    expect(source, contains('Once a host accepts a task'));
    expect(source, contains('controlled and are not reported'));
  });

  test('Native deploy docs preserve reporter ownership', () async {
    final document = await File('content/docs/deploy.mdc').readAsString();
    final source = document.replaceAll(RegExp(r'\s+'), ' ');

    expect(source, contains('creates the application `Server` once'));
    expect(source, contains('appServer.handler'));
    expect(source, contains('onError: appServer.onError'));
    expect(source, contains('without duplicating Server-owned'));
    expect(source, contains('response close attempt settles'));
    expect(source, contains('`HttpServer.close` does not await'));
    expect(source, contains('application-owned durable queue'));
  });

  test('Cloudflare hybrid example preserves dynamic page navigation', () async {
    final source = await File('content/docs/deploy.mdc').readAsString();
    final block = RegExp(r'```json\s+([\s\S]*?)\s+```').firstMatch(source);

    expect(block, isNotNull);
    final config = jsonDecode(block!.group(1)!) as Map<String, Object?>;
    final assets = config['assets']! as Map<String, Object?>;
    expect(config['compatibility_flags'], <String>['enable_request_signal']);
    expect(assets['directory'], './build/web');
    expect(assets['html_handling'], 'drop-trailing-slash');
    expect(assets, isNot(contains('not_found_handling')));
    expect(source, contains('generated directory indexes on canonical URLs'));
    expect(source, contains('navigation misses can reach dynamic'));
    expect(source, contains('For a fully prerendered SSG'));
    expect(source, contains('assets_navigation_has_no_effect'));
    expect(source, contains('completes `ServerRequest.cancelled`'));
    expect(source, contains('appServer.invocationHandler'));
    expect(source, contains('onError: appServer.onError'));
    expect(source, contains('response-byte conversion failures once'));
    expect(source, contains('host `waitUntil`'));
  });

  test('small secondary labels use accessible muted ink', () async {
    final css = await File('public/site.css').readAsString();

    expect(
      RegExp(
        r'\.footer-legal\s*\{[^}]*color:\s*var\(--muted\);',
        multiLine: true,
      ).hasMatch(css),
      isTrue,
    );
    expect(
      RegExp(
        r'\.docs-nav-group h2,\s*\.docs-outline h2\s*\{'
        r'[^}]*color:\s*var\(--muted\);',
        multiLine: true,
      ).hasMatch(css),
      isTrue,
    );
    expect(
      RegExp(
        r'\.docs-breadcrumb\s*\{[^}]*color:\s*var\(--muted\);',
        multiLine: true,
      ).hasMatch(css),
      isTrue,
    );
  });

  test('documentation tables own their horizontal overflow', () async {
    final css = await File('public/site.css').readAsString();
    final tableRule = RegExp(
      r'\.docs-article table\s*\{([^}]*)\}',
      multiLine: true,
    ).firstMatch(css);

    expect(tableRule, isNotNull);
    final declarations = tableRule!.group(1)!;
    expect(declarations, contains('display: block;'));
    expect(declarations, contains('max-width: 100%;'));
    expect(declarations, contains('overflow-x: auto;'));

    final mobileStart = css.indexOf('@media (max-width: 760px)');
    final reducedMotionStart = css.indexOf(
      '@media (prefers-reduced-motion',
      mobileStart,
    );
    expect(mobileStart, greaterThanOrEqualTo(0));
    expect(reducedMotionStart, greaterThan(mobileStart));
    final mobileCss = css.substring(mobileStart, reducedMotionStart);
    expect(
      RegExp(
            r'\.docs-article th,\s*\.docs-article td\s*\{([^}]*)\}',
            multiLine: true,
          )
          .allMatches(mobileCss)
          .any((match) => match.group(1)!.contains('min-width: 9rem;')),
      isTrue,
    );
  });
}

final _title = RegExp(r'<title>([^<]+)</title>');
final _canonical = RegExp(r'<link rel="canonical" href="([^"]+)">');

Iterable<RegExpMatch> _meta(String body, String property) => RegExp(
  '<meta property="${RegExp.escape(property)}" content="([^"]+)">',
).allMatches(body);

String _single(Iterable<RegExpMatch> matches, Uri location, String label) {
  final values = matches.toList(growable: false);
  expect(values, hasLength(1), reason: '${location.path}: $label');
  return values.single.group(1)!;
}

int _uint32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];
