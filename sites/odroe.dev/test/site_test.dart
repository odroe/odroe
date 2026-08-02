import 'dart:convert';
import 'dart:io';

import 'package:odroe/document.dart';
import 'package:odroe/mdc.dart';
import 'package:odroe/press.dart';
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
    'documentation navigation exposes the five-part information architecture',
    () async {
      expect(await docs.locations(), hasLength(17));
      final server = Server(
        routes: generated.serverRouteTree,
        functions: generated.serverFunctions,
        renderer: const DocumentRenderer(baseHref: '/').call,
      );
      final response = await server.handle(
        ServerRequest(
          method: HttpMethod.get,
          uri: Uri(path: '/docs/getting-started'),
          headers: Headers.single(<String, String>{'accept': 'text/html'}),
        ),
      );
      final body = await utf8.decodeStream(response.body);

      expect(response.status, 200);
      _expectInOrder('Documentation sections', body, <String>[
        '<h2>Start</h2>',
        '<h2>Tutorials</h2>',
        '<h2>Concepts</h2>',
        '<h2>Guides</h2>',
        '<h2>Reference</h2>',
      ]);
      expect(
        body,
        contains(
          'href="/docs/getting-started" aria-current="page">First product</a>',
        ),
      );
      expect(body, contains('href="/docs/tutorials/full-stack"'));
      expect(body, contains('href="/docs/guides/typed-rpc-records"'));
      expect(body, contains('href="/docs/reference/api"'));
    },
  );

  test('internal documentation links resolve to pages and headings', () async {
    final snapshot = await docs.snapshot();
    final pages = <String, PressPage>{
      for (final page in snapshot.pages) page.location.path: page,
    };
    final link = RegExp(r'\]\((/docs[^\s)#]*)(?:#([^\s)]+))?\)');

    for (final page in snapshot.pages) {
      final source = await File(
        'content/docs/${page.sourcePath}',
      ).readAsString();
      for (final match in link.allMatches(source)) {
        final path = match.group(1)!;
        final target = pages[path];
        expect(target, isNotNull, reason: '${page.sourcePath}: $path');
        final fragment = match.group(2);
        if (fragment != null) {
          expect(
            _outlineIds(target!.outline),
            contains(fragment),
            reason: '${page.sourcePath}: $path#$fragment',
          );
        }
      }
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
      expect(body, contains('RpcModule.http(baseUri: rpcBaseUri())'));
      expect(body, contains('Source preview'));
      expect(body, contains('Cloudflare preview'));
      expect(body, contains('Cloudflare Preview'));
      expect(body, contains('Verified locally'));
      expect(body, contains('explicitly choose a Flutter target'));
      expect(body, isNot(contains('Write the product once')));
      expect(body, isNot(contains('each runtime')));
      expect(body, isNot(contains('data models consistent')));
      expect(body, isNot(contains('Use only what you import')));
      expect(body, isNot(contains('enter the runtime artifact')));
      expect(body, contains('resolves one shared dependency graph'));
    },
  );

  test('homepage principle cards keep their layout contract', () async {
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
    final css = await File('public/site.css').readAsString();

    expect(response.status, 200);
    expect(
      RegExp(r'<article class="principle">').allMatches(body),
      hasLength(3),
    );
    expect(css, contains('.principle {'));
    expect(css, contains('.principle p {'));
  });

  test('social card is a 1200x630 PNG', () async {
    final bytes = await File('public/social-card.png').readAsBytes();
    final source = await File('public/social-card.svg').readAsString();

    expect(bytes.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    expect(_uint32(bytes, 16), 1200);
    expect(_uint32(bytes, 20), 630);
    expect(source, contains('Data · Cloudflare Preview'));
    expect(source, isNot(contains('Data · Edge')));
  });

  test('onboarding closes the full-stack native and edge paths', () async {
    final gettingStarted = await File(
      'content/docs/getting-started.mdc',
    ).readAsString();
    final tutorial = await File(
      'content/docs/tutorials/full-stack.mdc',
    ).readAsString();
    final deployment = await File(
      'content/docs/guides/deployment.mdc',
    ).readAsString();
    final readme = await File('../../README.md').readAsString();

    for (final source in <String>[readme, gettingStarted]) {
      expect(source, contains('flutter pub get'));
      expect(source, contains('dart run odroe init --full-stack'));
      expect(source, contains('dart run odroe dev -- -d chrome'));
      expect(source, contains('dart run odroe build --no-server web'));
      expect(
        source,
        contains('dart run odroe build --no-server -- web --wasm'),
      );
      _expectInOrder('Primary product path', source, <String>[
        'flutter pub get',
        'dart run odroe init --full-stack',
        'dart run odroe dev -- -d chrome',
      ]);
    }

    for (final marker in <String>[
      'posts.dart',
      'posts_database.dart',
      'rpc_origin.dart',
      'server_native.dart',
      'server_cloudflare.dart',
      'routes.server.dart',
      'migrations/0001_posts.sql',
      'package-lock.json',
      'wrangler.jsonc',
    ]) {
      expect(gettingStarted, contains(marker), reason: marker);
    }
    expect(gettingStarted, contains('dart run odroe dev --server-only'));
    expect(gettingStarted, contains('flutter devices'));
    expect(gettingStarted, contains('dart run odroe dev -- -d <device-id>'));
    expect(gettingStarted, contains('ODROE_API_ORIGIN'));
    expect(gettingStarted, contains('reuses stale HTML'));
    expect(gettingStarted, contains('SQLite post 42'));
    expect(gettingStarted, contains('D1 post 42'));
    expect(gettingStarted, contains('.odroe/app.sqlite3'));
    expect(gettingStarted, contains('ODROE_SQLITE_PATH'));
    expect(gettingStarted, contains('temporary database'));
    expect(gettingStarted, contains('serves the semantic handoff'));
    expect(gettingStarted, isNot(contains('cd ../odroe/example/app')));
    expect(gettingStarted, isNot(contains('/posts/42')));

    for (final entry in <String, String>{
      'README': _shellBlockContaining(
        readme,
        'npm run cloudflare:migrate:local',
      ),
      'Getting started': _shellBlockContaining(
        gettingStarted,
        'npm run cloudflare:migrate:local',
      ),
      'Deployment': _shellBlockContaining(
        deployment,
        'npm run cloudflare:migrate:local',
      ),
    }.entries) {
      expect(entry.value, isNot(contains('cd example/app')), reason: entry.key);
      expect(
        entry.value,
        isNot(contains('cd ../odroe/example/app')),
        reason: entry.key,
      );
      _expectInOrder(entry.key, entry.value, <String>[
        'npm ci',
        'dart run odroe build --no-server web',
        'npm run cloudflare:migrate:local',
        'npm run cloudflare:dev',
      ]);
    }

    expect(tutorial, contains('Post and CreatePost records'));
    expect(
      tutorial,
      contains('ServerFunction<models.CreatePost, models.Post>'),
    );
    expect(tutorial, contains('ServerFunction<String, List<models.Post>>'));
    expect(tutorial, contains('DatabaseModule.borrowed(database)'));
    expect(tutorial, contains('D1SqlDatabase'));
    expect(tutorial, contains('generated.routes.posts.createPost'));
    expect(tutorial, contains('final QueryKey<List<Post>> listKey'));
    expect(
      tutorial,
      contains("QueryFilter(key: QueryKey<Object?>('posts.list'))"),
    );
  });

  test('support matrix reports evidence and limits honestly', () async {
    final source = await File(
      'content/docs/reference/support.mdc',
    ).readAsString();

    expect(source, contains('| Flutter Web | Verified locally |'));
    expect(
      source,
      contains('| Flutter Android and iOS | Available, not yet verified |'),
    );
    expect(source, contains('no repository build, device, or store-release'));
    expect(source, contains('| Cloudflare Worker + D1 | Preview |'));
    expect(source, contains('| Remote Cloudflare deploy | Not claimed |'));
    expect(source, contains('typed SQL, not a full ORM'));
    expect(source, contains('multi-row inserts are one statement'));
    expect(source, contains('do not guarantee that returned rows'));
    expect(source, contains('same exact `QueryKey<T>` data type'));
    expect(source, contains('there is no streaming database query'));
    expect(source, isNot(contains('all major databases')));
    expect(source, isNot(contains('one-click deployment')));
  });

  test('cross-platform RPC examples require a native HTTP origin', () async {
    final readme = await File('../../README.md').readAsString();
    final overview = await File('content/docs/index.mdc').readAsString();
    final gettingStarted = await File(
      'content/docs/getting-started.mdc',
    ).readAsString();
    final query = await File('content/docs/concepts/query.mdc').readAsString();
    final server = await File(
      'content/docs/guides/server-operations.mdc',
    ).readAsString();
    final homepage = await File('lib/site/home.dart').readAsString();

    expect(readme, contains("import 'rpc_origin.dart';"));
    expect(readme, contains('Uri? rpcBaseUri('));
    expect(readme, contains('RpcModule.http(baseUri: rpcBaseUri())'));
    expect(readme, isNot(contains('\ndart run odroe dev\n')));
    expect(
      readme,
      contains(
        'dart run odroe dev -- -d <ios-device-id> '
        '--dart-define=ODROE_API_ORIGIN=https://api.example.com',
      ),
    );
    expect(
      readme,
      contains(
        'dart run odroe build --no-server -- apk '
        '--dart-define=ODROE_API_ORIGIN=https://api.example.com',
      ),
    );
    expect(overview, contains('RpcModule.http(baseUri: rpcBaseUri())'));
    expect(gettingStarted, contains('ODROE_API_ORIGIN'));
    expect(query, contains('baseUri: rpcBaseUri(),'));
    expect(server, contains('## Client origin'));
    expect(server, contains('Android, iOS, and desktop apps must pass'));
    expect(server, contains('baseUri: rpcBaseUri(),'));
    expect(homepage, contains('RpcModule.http(baseUri: rpcBaseUri())'));
    expect(homepage, contains(r'$ dart run odroe init'));
    expect(homepage, contains(r'$ dart run odroe dev -- -d chrome'));
    expect(homepage, contains(r'$ dart run odroe build --no-server web'));

    for (final entry in <String, String>{
      'README': readme,
      'Overview': overview,
      'Getting started': gettingStarted,
      'Query': query,
      'Server': server,
    }.entries) {
      for (final match in RegExp(
        r'```dart\s+([\s\S]*?)\s+```',
      ).allMatches(entry.value)) {
        for (final call in _rpcModuleCalls(match.group(1)!)) {
          expect(
            call,
            contains('baseUri: rpcBaseUri()'),
            reason: '${entry.key} contains a native-unsafe RPC example.',
          );
        }
      }
    }
  });

  test('extension key docs require one shared identity', () async {
    final app = (await File(
      'content/docs/concepts/application.mdc',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');
    final routing = (await File(
      'content/docs/concepts/routing.mdc',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');
    final server = (await File(
      'content/docs/guides/server-operations.mdc',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');

    expect(
      app,
      contains("final buildLabelKey = ContextKey<String>('build-label');"),
    );
    expect(app, contains('matched by instance identity'));
    expect(app, contains('reuse that exact instance'));
    expect(app, contains('buildLabelKey.provide(registry, label)'));
    expect(app, contains('context.read(buildLabelKey)'));
    expect(app, contains('replaces the old `const ContextKey(...)` form'));
    expect(
      app,
      contains('buildLabelKey.provideFactory(registry, createLabel)'),
    );
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
    expect(app, isNot(contains('const buildLabelKey = ContextKey')));
  });

  test('routing docs preserve live browser path and search state', () async {
    final routing = (await File(
      'content/docs/concepts/routing.mdc',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');
    final readme = (await File(
      '../../README.md',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');

    expect(routing, contains('set `webPathUrls: true`'));
    expect(routing, contains("install Flutter's official path URL"));
    expect(routing, contains('before `runApp`'));
    expect(routing, contains("preserves Flutter's or the host's existing"));
    expect(routing, contains('discards those stale loads and Query data'));
    expect(routing, contains('`webPathUrls: false`'));
    expect(readme, contains('`webPathUrls: true`'));
    expect(readme, contains('安装 Flutter 官方 Path URL strategy'));
    expect(readme, contains('保留 Flutter 或宿主应用已经选择的 URL strategy'));
    expect(readme, contains('惰性 modules'));
    expect(readme, contains('旧 loads/query handoff'));
    expect(readme, contains('`webPathUrls: false`'));
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
      expect(config, isNot(contains('main')));
      expect(assets, isNot(contains('run_worker_first')));
    },
  );

  test('website operations stay locked and out of public docs', () async {
    final package =
        jsonDecode(await File('package.json').readAsString())
            as Map<String, Object?>;
    final scripts = package['scripts']! as Map<String, Object?>;
    final dependencies = package['devDependencies']! as Map<String, Object?>;
    final lock =
        jsonDecode(await File('package-lock.json').readAsString())
            as Map<String, Object?>;
    final packages = lock['packages']! as Map<String, Object?>;
    final root = packages['']! as Map<String, Object?>;
    final wrangler = packages['node_modules/wrangler']! as Map<String, Object?>;
    final operations = await File('README.md').readAsString();
    final publicDeployment = await File(
      'content/docs/guides/deployment.mdc',
    ).readAsString();

    expect(package['private'], isTrue);
    expect(package['engines'], <String, Object?>{'node': '>=22.0.0'});
    expect(await File('.npmrc').readAsString(), 'engine-strict=true\n');
    expect(dependencies, <String, Object?>{'wrangler': '4.118.0'});
    expect(root['devDependencies'], dependencies);
    expect(root['engines'], package['engines']);
    expect(wrangler['version'], '4.118.0');
    expect(scripts['build'], 'dart run odroe build --no-server');
    expect(scripts['preview'], 'wrangler dev --local');
    expect(
      scripts['deploy:check'],
      'wrangler deploy --dry-run --strict --outdir .wrangler/dry-run',
    );
    expect(scripts['deploy'], 'wrangler deploy --strict');
    expect(scripts['deploy:account'], 'wrangler whoami --json');
    expect(scripts['deploy:status'], 'wrangler deployments status --json');
    expect(scripts['deploy:versions'], 'wrangler versions list --json');

    expect(operations, contains('## Local quality gate'));
    expect(operations, contains('npm run deploy:check'));
    expect(operations, contains('does not authenticate or upload'));
    expect(operations, contains('## Remote deployment authorization'));
    expect(operations, contains('requires explicit authorization'));
    expect(operations, contains('CLOUDFLARE_ACCOUNT_ID'));
    expect(operations, contains('npm run deploy:account'));
    expect(operations, contains('ODROE_DEPLOY_SHA'));
    expect(operations, contains('npm run deploy:status'));
    expect(operations, contains('npm run deploy:versions'));
    expect(operations, contains('100% of traffic'));
    final deploymentGate = RegExp(
      r'The application gate is:\n\n```sh\n(\([\s\S]*?\n\))\n```',
    ).firstMatch(operations)?.group(1);
    expect(deploymentGate, isNotNull);
    expect(deploymentGate, startsWith('(\n  set -eu\n'));
    expect(
      deploymentGate!.indexOf('npm run deploy --'),
      greaterThan(deploymentGate.indexOf('npm run deploy:check')),
    );
    expect(
      RegExp(
        RegExp.escape(r'test -z "$(git status --porcelain)"'),
      ).allMatches(operations),
      hasLength(2),
    );

    expect(publicDeployment, isNot(contains('odroe-dev')));
    expect(publicDeployment, isNot(contains('CLOUDFLARE_ACCOUNT_ID')));
    expect(publicDeployment, isNot(contains('ODROE_DEPLOY_SHA')));
    expect(publicDeployment, isNot(contains('DNS')));
    expect(publicDeployment, isNot(contains('certificate')));
  });

  test('search assets match published pages and exact migrations', () async {
    final server = Server(
      routes: generated.serverRouteTree,
      functions: generated.serverFunctions,
      renderer: const DocumentRenderer(baseHref: '/').call,
    );
    final canonicalUrls = <String>[];
    for (final location in <Uri>[Uri(path: '/'), ...await docs.locations()]) {
      final response = await server.handle(
        ServerRequest(
          method: HttpMethod.get,
          uri: location,
          headers: Headers.single(<String, String>{'accept': 'text/html'}),
        ),
      );
      final body = await utf8.decodeStream(response.body);
      canonicalUrls.add(
        _single(_canonical.allMatches(body), location, 'canonical'),
      );
    }
    canonicalUrls.sort();

    final sitemap = await File('public/sitemap.xml').readAsString();
    final sitemapUrls = RegExp(
      r'<loc>([^<]+)</loc>',
    ).allMatches(sitemap).map((match) => match.group(1)!).toList()..sort();
    expect(sitemapUrls, canonicalUrls);
    expect(sitemapUrls.toSet(), hasLength(sitemapUrls.length));
    expect(sitemapUrls, isNot(contains('https://odroe.dev/404.html')));
    expect(
      await File('public/robots.txt').readAsString(),
      'User-agent: *\n'
      'Allow: /\n'
      '\n'
      'Sitemap: https://odroe.dev/sitemap.xml\n',
    );

    final redirects = <String, String>{};
    for (final line in await File('public/_redirects').readAsLines()) {
      if (line.trim().isEmpty) continue;
      final fields = line.trim().split(RegExp(r'\s+'));
      expect(fields, hasLength(3), reason: line);
      final source = fields[0];
      final destination = fields[1];
      expect(fields[2], '301', reason: line);
      expect(source, startsWith('/'), reason: line);
      expect(source, isNot(contains('*')), reason: line);
      expect(redirects, isNot(contains(source)), reason: line);
      redirects[source] = destination;
    }
    expect(redirects, _legacyRedirects);

    final canonicalPaths = canonicalUrls
        .map((url) => Uri.parse(url).path)
        .toSet();
    for (final entry in redirects.entries) {
      expect(sitemapUrls, isNot(contains('https://odroe.dev${entry.key}')));
      expect(canonicalPaths, isNot(contains(entry.key)));
      expect(redirects, isNot(contains(entry.value)));
      if (entry.value.startsWith('/')) {
        expect(canonicalPaths, contains(entry.value), reason: entry.key);
      } else {
        final destination = Uri.parse(entry.value);
        expect(destination.scheme, 'https', reason: entry.key);
        expect(destination.host, isNotEmpty, reason: entry.key);
      }

      final location = Uri(path: entry.key);
      final response = await server.handle(
        ServerRequest(
          method: HttpMethod.get,
          uri: location,
          headers: Headers.single(<String, String>{'accept': 'text/html'}),
        ),
      );
      final body = await utf8.decodeStream(response.body);
      expect(response.status, 404, reason: entry.key);
      expect(_canonical.allMatches(body), isEmpty, reason: entry.key);
    }
  });

  test('Query docs match key and mutation lifecycle contracts', () async {
    final source = (await File(
      'content/docs/concepts/query.mdc',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');

    final options = QueryOptions<int>(
      key: QueryKey('post', <Object?>[42]),
      query: (_) async => 42,
    );
    expect(options.key, QueryKey('post', <Object?>[42]));
    expect(
      source,
      contains("key: QueryKey<String>('post', <Object?>[postId]),"),
    );
    expect(source, isNot(contains("QueryKey(<Object?>['post', postId])")));
    expect(source, contains('Nested lists and string-keyed maps are copied'));
    expect(source, contains('cannot change cache identity, prefix matching'));
    expect(source, contains('exact query-cache data contract'));
    expect(source, contains('`QueryKey<int>` to `QueryKey<num>`'));
    expect(source, contains('leaves the existing query entry intact'));
    expect(source, contains('Mutation keys are operation identities'));
    expect(source, contains('`QueryKey<Object?>` for a standalone prefix'));
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
    expect(source, contains('MutationCancelledException'));
    expect(source, contains('cannot roll back its side effects'));
    expect(source, contains('returns the latest cache projection'));
    expect(source, contains('reuses an active fetch'));
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
    expect(source, contains('baseUri: rpcBaseUri(),'));
    expect(source, contains('serializer: serializer'));
    expect(source, contains('DocumentModule(serializer: serializer)'));
    expect(source, contains('hydration restores a dynamic placeholder'));
    expect(source, contains('Completed data is validated before'));
    expect(source, contains('Pending options may adopt immediately'));
    expect(source, contains('leaves the typed query in error'));
  });

  test('Database docs preserve the typed dialect boundary', () async {
    final document = await File(
      'content/docs/guides/database-providers.mdc',
    ).readAsString();
    final source = document.replaceAll(RegExp(r'\s+'), ' ');
    final fullStack = _shellBlockContaining(
      document,
      'npm run cloudflare:migrate:local',
    );

    expect(source, contains('preserves its selected dialect'));
    expect(source, contains('SQLite and D1 accept `SqlDialect.sqlite`'));
    expect(source, contains('PostgreSQL accepts `SqlDialect.postgres`'));
    expect(source, contains('MySQL/MariaDB accepts `SqlDialect.mysql`'));
    expect(source, contains('`SqlErrorCode.unsupported`'));
    expect(source, contains('before that statement reaches the database'));
    expect(source, contains('dialect: SqlDialect.postgres'));
    expect(source, contains('default to `dialect: null`'));
    expect(source, contains('does not prove that the SQL is portable'));
    expect(source, contains('`insertMany` compiles one multi-row `INSERT`'));
    expect(source, contains('requires at least one row'));
    expect(source, contains('at least one assignment per row'));
    expect(source, contains('before SQL construction or I/O'));
    expect(source, contains('not an `atomicWrite` batch'));
    expect(source, contains('does not auto-chunk'));
    expect(source, contains('does not promise input order'));
    expect(source, contains('MySQL/MariaDB executes the multi-row write'));
    expect(source, contains('Future<void> close()'));
    expect(source, contains('DatabaseModule.owned'));
    expect(source, contains('DatabaseModule.borrowed'));
    expect(source, contains('app.read(databaseKey)'));
    expect(source, contains('onClose: database.close'));
    expect(source, contains('## One query, two runtimes'));
    expect(source, contains('generated typed RPC'));
    expect(source, contains('locked local Wrangler toolchain'));
    expect(source, contains('npm run cloudflare:migrate:local'));
    expect(source, contains('npm run cloudflare:dev'));
    _expectInOrder('Database docs', fullStack, <String>[
      'flutter pub get',
      'npm ci',
      'dart run odroe build --no-server web',
      'npm run cloudflare:migrate:local',
      'npm run cloudflare:dev',
    ]);
  });

  test('full-stack database example keeps platform drivers isolated', () async {
    const example = '../../example/app';
    final entry = await File('$example/lib/server.dart').readAsString();
    final native = await File('$example/lib/server_native.dart').readAsString();
    final nativeDatabase = await File(
      '$example/lib/posts_database.dart',
    ).readAsString();
    final cloudflare = await File(
      '$example/lib/server_cloudflare.dart',
    ).readAsString();
    final route = await File(
      '$example/lib/routes/posts/[postId]/server.dart',
    ).readAsString();
    final migration = await File(
      '$example/migrations/0001_posts.sql',
    ).readAsString();
    final exampleReadme = await File('$example/README.md').readAsString();
    final exampleFullStack = _shellBlockContaining(
      exampleReadme,
      'npm run cloudflare:migrate:local',
    );
    final deployment = await File(
      'content/docs/guides/deployment.mdc',
    ).readAsString();
    final package =
        jsonDecode(await File('$example/package.json').readAsString())
            as Map<String, Object?>;
    final packageLock =
        jsonDecode(await File('$example/package-lock.json').readAsString())
            as Map<String, Object?>;
    final pubIgnore = await File('../../.pubignore').readAsLines();
    final lockPackages = packageLock['packages']! as Map<String, Object?>;
    final lockedRoot = lockPackages['']! as Map<String, Object?>;
    final lockedWrangler =
        lockPackages['node_modules/wrangler']! as Map<String, Object?>;
    final config =
        jsonDecode(await File('$example/wrangler.jsonc').readAsString())
            as Map<String, Object?>;
    final databases = config['d1_databases']! as List<Object?>;
    final database = databases.single as Map<String, Object?>;

    expect(entry, contains("if (dart.library.io) 'server_native.dart'"));
    expect(native, contains("package:odroe/database_sqlite.dart"));
    expect(native, contains('FutureOr<Server> createServer()'));
    expect(native, contains("ODROE_SQLITE_PATH']"));
    expect(native, contains("'.odroe/app.sqlite3'"));
    expect(native, contains('SqliteDatabase.open(databaseFile.path)'));
    expect(native, contains('await initializePostsDatabase(database)'));
    expect(native, contains('DatabaseModule.borrowed(database)'));
    expect(native, contains('onClose: database.close'));
    expect(native, isNot(contains('database_d1.dart')));
    expect(nativeDatabase, contains('CREATE TABLE IF NOT EXISTS posts'));
    expect(nativeDatabase, contains('SqlTable<Post>'));
    expect(nativeDatabase, contains('.insertOnConflictDoNothing('));
    expect(nativeDatabase, contains('target: [posts.id]'));
    expect(nativeDatabase, isNot(contains('INSERT INTO posts')));
    expect(cloudflare, contains("package:odroe/database_d1.dart"));
    expect(cloudflare, contains('FutureOr<Server> createServer()'));
    expect(cloudflare, contains('invocationModules: (invocation)'));
    expect(cloudflare, contains("@JS('DB')"));
    expect(cloudflare, isNot(contains('database_sqlite.dart')));
    expect(route, contains("package:odroe/database.dart"));
    expect(route, contains("package:odroe/server.dart"));
    expect(route, isNot(contains("package:odroe/rpc.dart")));
    expect(route, contains('context.request.read(databaseKey)'));
    expect(route, contains("const NotFound('Post not found.')"));
    expect(route, contains('return post;'));
    expect(route, isNot(contains('database_sqlite.dart')));
    expect(route, isNot(contains('database_d1.dart')));
    expect(route, isNot(contains(r'Post ${context.data}')));
    expect(migration, contains('CREATE TABLE posts'));
    expect(migration, contains("VALUES (42, 'D1 post 42')"));
    expect(config['main'], './build/odroe/cloudflare/worker.mjs');
    expect(config[r'$schema'], './node_modules/wrangler/config-schema.json');
    expect(config['compatibility_date'], '2026-08-01');
    expect(config['compatibility_flags'], contains('enable_request_signal'));
    expect(database['binding'], 'DB');
    expect(database['migrations_dir'], 'migrations');
    expect(exampleReadme, contains('Flutter\nQuery / Mutation'));
    expect(exampleReadme, contains('SQLite post 42'));
    expect(exampleReadme, contains('D1 post 42'));
    expect(package['private'], isTrue);
    expect(package['engines'], <String, Object?>{
      'node': '>=22.0.0',
      'npm': '>=10.9.0',
    });
    expect(package['devEngines'], <String, Object?>{
      'runtime': <String, Object?>{
        'name': 'node',
        'version': '>=22.0.0',
        'onFail': 'error',
      },
      'packageManager': <String, Object?>{
        'name': 'npm',
        'version': '>=10.9.0',
        'onFail': 'error',
      },
    });
    expect(package['devDependencies'], <String, Object?>{
      'wrangler': '4.118.0',
    });
    expect(package['scripts'], <String, Object?>{
      'cloudflare:migrate:local': 'wrangler d1 migrations apply DB --local',
      'cloudflare:dev':
          'dart run odroe dev --server-target cloudflare --server-only',
    });
    expect(packageLock['lockfileVersion'], 3);
    expect(lockedRoot['devDependencies'], package['devDependencies']);
    expect(lockedRoot['engines'], package['engines']);
    expect(lockedWrangler['version'], '4.118.0');
    expect(pubIgnore, contains('node_modules/'));
    expect(pubIgnore, contains('.wrangler/'));
    expect(pubIgnore, contains('.odroe/'));
    expect(exampleReadme, contains('npm ci'));
    expect(exampleReadme, contains('`engines`'));
    expect(exampleReadme, contains('`devEngines`'));
    expect(exampleReadme, contains('npm run cloudflare:migrate:local'));
    expect(exampleReadme, contains('npm run cloudflare:dev'));
    _expectInOrder('Example README', exampleFullStack, <String>[
      'flutter pub get',
      'npm ci',
      'dart run odroe build --no-server web',
      'npm run cloudflare:migrate:local',
      'npm run cloudflare:dev',
    ]);
    expect(deployment, contains('`odroe init --full-stack`'));
    expect(deployment, contains('owns a locked Wrangler toolchain'));
    expect(deployment, contains('npm run cloudflare:migrate:local'));
    expect(deployment, contains('npm run cloudflare:dev'));
    expect(deployment, contains('Removing `--local` changes the remote'));
    expect(
      deployment,
      contains('ODROE_SQLITE_PATH=/persistent/odroe/app.sqlite3'),
    );
    expect(deployment, contains('application-owned migration'));
  });

  test('Constructor dependency types stay on product entrypoints', () async {
    final database = await File(
      'content/docs/guides/database-providers.mdc',
    ).readAsString();
    final server = await File(
      'content/docs/guides/server-operations.mdc',
    ).readAsString();
    final readme = await File('../../README.md').readAsString();

    expect(
      database,
      contains("import 'package:odroe/database_postgres.dart';"),
    );
    expect(database, contains('PoolSettings(maxConnectionCount: 4)'));
    expect(database, contains('`Connection`, `ConnectionSettings`, `Pool`'));
    expect(database, isNot(contains('pg.Pool')));
    expect(server, contains('`Client.send`'));
    expect(server, contains('Extending `BaseClient`'));
    expect(server, contains('complete server product entrypoint'));
    expect(server, contains('server implementations stay'));
    expect(server, contains('controlled `NotFound` and `Redirect`'));
    expect(server, contains('Every typed frame must use `version: 1`'));
    expect(server, contains("a `redirect` frame's status must equal"));
    expect(server, isNot(contains('http.Client')));
    expect(readme, contains('`Client.send`'));
    expect(readme, contains('实现 `BaseClient`'));
    expect(readme, isNot(contains('http.Client')));
  });

  test(
    'Lifecycle ownership is consistent across public documentation',
    () async {
      final app = await File(
        'content/docs/concepts/application.mdc',
      ).readAsString();
      final server = await File(
        'content/docs/guides/server-operations.mdc',
      ).readAsString();
      final database = await File(
        'content/docs/guides/database-providers.mdc',
      ).readAsString();
      final deploy = await File(
        'content/docs/guides/deployment.mdc',
      ).readAsString();
      final readme = await File('../../README.md').readAsString();

      expect(app, contains('ownership transfers as each module is yielded'));
      expect(app, contains('DatabaseModule.borrowed(database)'));
      expect(app, contains('DatabaseModule.owned(sharedDatabase)'));
      expect(app, contains('`Server` `onClose` callback owns'));
      expect(server, contains('`Server.close()` immediately rejects'));
      expect(server, contains('Concurrent and repeated calls return the same'));
      expect(
        server,
        contains('Do not await `Server.close()` from the current'),
      );
      expect(
        server,
        contains('`IoServer.close` stops the listener and drains'),
      );
      expect(server, contains('Fetch bootstrap does not call `onClose`'));
      expect(database, contains('Future<void> close();'));
      expect(database, contains('DatabaseModule.owned'));
      expect(database, contains('DatabaseModule.borrowed'));
      expect(database, contains('onClose: database.close'));
      expect(database, contains('Future<Server> createServer() async'));
      expect(database, contains('MysqlDatabase.open'));
      expect(database, contains('invocationModules: (invocation)'));
      expect(database, contains('invocation.requireBindings<FetchBindings>()'));
      expect(database, contains('D1SqlDatabase.fromBinding(environment.DB)'));
      expect(deploy, contains('await IoServer.close(nativeServer)'));
      expect(deploy, contains('await appServer.close()'));
      expect(deploy, contains('`HttpServer.close` does not await'));
      expect(
        deploy,
        contains('Fetch runtime has no reliable process-shutdown'),
      );
      expect(readme, contains('DatabaseModule.borrowed(database)'));
      expect(readme, contains('onClose: database.close'));
      expect(readme, contains('`IoServer.close`'));
    },
  );

  test('Server docs close the authenticated RPC contract', () async {
    final source = await File(
      'content/docs/guides/server-operations.mdc',
    ).readAsString();
    final appSource = await File(
      'content/docs/concepts/application.mdc',
    ).readAsString();

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
    expect(source, contains('Return `null` on Web'));
    expect(source, contains('Android, iOS, and desktop apps'));
    expect(source, contains('apps must pass'));
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
      'content/docs/guides/server-operations.mdc',
    ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');

    expect(source, contains('`Server.maxFunctionPayload`'));
    expect(source, contains('four independent byte boundaries'));
    expect(source, contains('`Server.maxFunctionResponseFrameBytes`'));
    expect(source, contains('defaults to 1 MiB'));
    expect(source, contains('minimum is 28 bytes'));
    expect(source, contains('`{"version":1,"type":"error"}`'));
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
    final document = await File(
      'content/docs/guides/server-operations.mdc',
    ).readAsString();
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
    expect(source, contains('`IoServer.close` stops the listener and drains'));
    expect(source, contains('`Server.close()` immediately rejects'));
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
    final document = await File(
      'content/docs/guides/deployment.mdc',
    ).readAsString();
    final source = document.replaceAll(RegExp(r'\s+'), ' ');

    expect(source, contains('creates the application `Server` once'));
    expect(source, contains('appServer.handler'));
    expect(source, contains('onError: appServer.onError'));
    expect(source, contains('without duplicating Server-owned'));
    expect(source, contains('response close attempt settles'));
    expect(source, contains('`HttpServer.close` does not await'));
    expect(source, contains('await IoServer.close(nativeServer)'));
    expect(source, contains('await appServer.close()'));
    expect(source, contains('second signal during that drain escalates'));
    expect(source, contains('application-owned durable queue'));
  });

  test('Cloudflare hybrid example preserves dynamic page navigation', () async {
    final source = await File(
      'content/docs/guides/deployment.mdc',
    ).readAsString();
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
const _legacyRedirects = <String, String>{
  '/packages/oref': 'https://oref.medz.dev/',
  '/packages/alien-signals':
      'https://github.com/medz/alien-signals-dart/blob/main/docs/guide.md',
  '/packages/oinject': 'https://pub.dev/packages/oinject',
  '/packages/oinject/': 'https://pub.dev/packages/oinject',
  '/packages/oncecall': 'https://pub.dev/packages/oncecall',
  '/zh/packages/oref': 'https://oref.medz.dev/zh/',
  '/zh/packages/alien-signals':
      'https://github.com/medz/alien-signals-dart/blob/main/docs/guide.md',
  '/zh/packages/oinject': 'https://pub.dev/packages/oinject',
  '/zh/packages/oncecall': 'https://pub.dev/packages/oncecall',
  '/zh/': '/',
  '/docs/oinject': 'https://pub.dev/packages/oinject',
  '/docs/oncecall': 'https://pub.dev/packages/oncecall',
  '/docs/oref/': 'https://oref.medz.dev/zh/guide/getting-started',
  '/docs/oref/introduction': 'https://oref.medz.dev/guide/getting-started',
  '/docs/oref/get-started': 'https://oref.medz.dev/guide/getting-started',
  '/docs/oref/core': 'https://oref.medz.dev/guide/core-concepts',
  '/docs/oref/advanced': 'https://oref.medz.dev/guide/effects',
  '/docs/oref/utils': 'https://pub.dev/documentation/oref/latest/oref/',
  '/zh/docs/oinject': 'https://pub.dev/packages/oinject',
  '/zh/docs/oncecall': 'https://pub.dev/packages/oncecall',
  '/zh/docs/oref/introduction':
      'https://oref.medz.dev/zh/guide/getting-started',
  '/zh/docs/oref/get-started': 'https://oref.medz.dev/zh/guide/getting-started',
  '/zh/docs/oref/core': 'https://oref.medz.dev/zh/guide/core-concepts',
  '/zh/docs/oref/advanced': 'https://oref.medz.dev/zh/guide/effects',
  '/zh/docs/oref/utils': 'https://pub.dev/documentation/oref/latest/oref/',
  '/docs/core/app': '/docs/concepts/application',
  '/docs/core/routing': '/docs/concepts/routing',
  '/docs/core/query': '/docs/concepts/query',
  '/docs/web/document': '/docs/concepts/content',
  '/docs/server': '/docs/concepts/server-rpc',
  '/docs/data/database': '/docs/concepts/database',
  '/docs/deploy': '/docs/guides/deployment',
};

Iterable<RegExpMatch> _meta(String body, String property) => RegExp(
  '<meta property="${RegExp.escape(property)}" content="([^"]+)">',
).allMatches(body);

String _single(Iterable<RegExpMatch> matches, Uri location, String label) {
  final values = matches.toList(growable: false);
  expect(values, hasLength(1), reason: '${location.path}: $label');
  return values.single.group(1)!;
}

String _shellBlockContaining(String source, String marker) {
  for (final match in RegExp(r'```sh\n([\s\S]*?)\n```').allMatches(source)) {
    final block = match.group(1)!;
    if (block.contains(marker)) return block;
  }
  throw StateError('Missing shell block containing $marker.');
}

void _expectInOrder(String label, String source, Iterable<String> values) {
  var offset = -1;
  for (final value in values) {
    final next = source.indexOf(value, offset + 1);
    expect(next, greaterThan(offset), reason: '$label: $value');
    offset = next;
  }
}

Iterable<String> _outlineIds(Iterable<MdcOutlineEntry> entries) sync* {
  for (final entry in entries) {
    yield entry.id;
    yield* _outlineIds(entry.children);
  }
}

int _uint32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

Iterable<String> _rpcModuleCalls(String source) sync* {
  const prefix = 'RpcModule.http(';
  var offset = 0;
  while (true) {
    final start = source.indexOf(prefix, offset);
    if (start < 0) return;

    var depth = 1;
    var end = start + prefix.length;
    while (end < source.length && depth > 0) {
      final character = source.codeUnitAt(end);
      if (character == 0x28) depth++;
      if (character == 0x29) depth--;
      end++;
    }
    if (depth != 0) throw FormatException('Unclosed RpcModule.http example.');
    yield source.substring(start, end);
    offset = end;
  }
}
