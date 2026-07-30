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
      expect(
        body,
        location.path == '/404.html'
            ? isNot(contains('<link rel="canonical"'))
            : contains('<link rel="canonical"'),
      );
      expect(body, isNot(contains('flutter_bootstrap.js')));
    }
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
    expect(body, isNot(contains('<link rel="canonical"')));
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
  });
}
