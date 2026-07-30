import 'dart:convert';
import 'dart:io';

import 'package:odroe/document.dart';
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
          'Typed Server, Data, and Edge.',
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
      expect(body, isNot(contains('data models consistent')));
      expect(body, isNot(contains('Use only what you import')));
    },
  );

  test('social card is a 1200x630 PNG', () async {
    final bytes = await File('public/social-card.png').readAsBytes();

    expect(bytes.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    expect(_uint32(bytes, 16), 1200);
    expect(_uint32(bytes, 20), 630);
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

  test('deployment serves canonical URLs without trailing slashes', () async {
    final config =
        jsonDecode(await File('wrangler.jsonc').readAsString())
            as Map<String, Object?>;
    final assets = config['assets']! as Map<String, Object?>;

    expect(assets['html_handling'], 'drop-trailing-slash');
  });

  test('Query docs keep mutation lifecycle boundaries explicit', () async {
    final source = (await File(
      'content/docs/core/query.mdc',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');

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
