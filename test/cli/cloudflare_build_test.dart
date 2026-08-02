import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/dart_command_lock.dart';
import '../support/process.dart';

void main() {
  test(
    'build emits a runnable Cloudflare Worker without dynamic evaluation',
    () async {
      final project = Directory('example/app').absolute;
      final output = Directory('${project.path}/build/odroe/cloudflare-test');
      addTearDown(() async {
        if (output.existsSync()) await output.delete(recursive: true);
      });

      await _buildWorker(project, 'build/odroe/cloudflare-test/server.js');

      final server = File('${output.path}/server.js');
      final worker = File('${output.path}/worker.mjs');
      expect(server.existsSync(), isTrue);
      expect(worker.existsSync(), isTrue);
      final bootstrap = await File(
        p.join(project.path, '.dart_tool', 'odroe', 'server_fetch.dart'),
      ).readAsString();
      expect(
        bootstrap,
        contains('final Object createdServer = app.createServer();'),
      );
      expect(
        bootstrap,
        contains('Cloudflare createServer() must return Server synchronously.'),
      );
      expect(bootstrap, contains('final appServer = createdServer;'));
      expect(bootstrap, contains('appServer.invocationHandler'));
      expect(bootstrap, contains('onError: appServer.onError'));
      expect('app.createServer()'.allMatches(bootstrap), hasLength(1));
      final javaScript = await server.readAsString();
      expect(javaScript, isNot(matches(RegExp(r'\beval\s*\('))));
      expect(javaScript, isNot(matches(RegExp(r'\bnew\s+Function\s*\('))));
      expect(await server.length(), lessThan(500 * 1024));
      final dependencies = await File('${server.path}.deps').readAsString();
      expect(dependencies, contains('server_cloudflare.dart'));
      expect(dependencies, contains('database_d1.dart'));
      expect(dependencies, isNot(contains('database_sqlite.dart')));
      expect(dependencies, isNot(contains('/sqlite3-')));
      expect(dependencies, isNot(contains('/lib/ffi/')));

      final smoke = await runTestProcess('node', <String>[
        '--input-type=module',
        '--eval',
        '''
globalThis.self = globalThis;
const worker = (await import(${Uri.file(worker.path).toString().quote()})).default;
const response = await worker.fetch(
  new Request('https://example.test/posts/42?preview=true', {
    headers: {accept: 'application/json'},
  }),
  {DB: {}},
  {waitUntil() {}},
);
if (response.status !== 200) throw new Error(`status \${response.status}`);
const body = await response.text();
if (!body.includes('"location":"/posts/42?preview=true"')) {
  throw new Error(body);
}
''',
      ], timeout: const Duration(seconds: 30));
      expect(smoke.exitCode, 0, reason: '${smoke.stdout}\n${smoke.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('prerender route limits fail before replacing build output', () async {
    final project = Directory('sites/odroe.dev').absolute;
    final output = Directory(
      p.join(project.path, 'build', 'prerender-limit-test'),
    )..createSync(recursive: true);
    final sentinel = File(p.join(output.path, 'sentinel.txt'))
      ..writeAsStringSync('keep');
    final artifactDirectory = Directory(
      p.join(project.path, 'build', 'odroe', 'prerender-limit-test'),
    );
    addTearDown(() {
      if (output.existsSync()) output.deleteSync(recursive: true);
      if (artifactDirectory.existsSync()) {
        artifactDirectory.deleteSync(recursive: true);
      }
    });
    final errors = StringBuffer();

    final code = await runOdroe(
      <String>[
        'build',
        '--project',
        project.path,
        '--server-target',
        'cloudflare',
        '--server-artifact',
        'build/odroe/prerender-limit-test/server.js',
        '--prerender-output',
        'build/prerender-limit-test',
        '--prerender-max-routes',
        '1',
      ],
      output: StringBuffer(),
      errors: errors,
    );

    expect(code, 1);
    expect(errors.toString(), 'Prerender locations exceed the limit of 1.\n');
    expect(sentinel.readAsStringSync(), 'keep');
    expect(artifactDirectory.existsSync(), isFalse);
  });

  test('server artifacts cannot overlap prerender output', () async {
    final project = Directory('sites/odroe.dev').absolute;
    final outputs = <Directory>[
      Directory(p.join(project.path, 'build', 'overlap-test')),
      Directory(p.join(project.path, 'build', 'overlap-case')),
      Directory(
        p.join(project.path, 'build', 'cloudflare-sidecar', 'worker.mjs'),
      ),
      Directory(
        p.join(project.path, 'build', 'cloudflare-deps', 'server.js.deps'),
      ),
    ];
    addTearDown(() {
      for (final output in outputs) {
        if (output.existsSync()) output.deleteSync(recursive: true);
      }
    });

    final cases = <({String artifact, String output, String target})>[
      (
        artifact: 'build/overlap-test/server',
        output: 'build/overlap-test',
        target: 'native',
      ),
      (
        artifact: 'build/overlap-test/server.js',
        output: 'build/overlap-test',
        target: 'cloudflare',
      ),
      (
        artifact: 'build/Overlap-Case/server.js',
        output: 'build/overlap-case',
        target: 'cloudflare',
      ),
      (
        artifact: 'build/cloudflare-sidecar/server.js',
        output: 'build/cloudflare-sidecar/worker.mjs',
        target: 'cloudflare',
      ),
      (
        artifact: 'build/cloudflare-deps/server.js',
        output: 'build/cloudflare-deps/server.js.deps',
        target: 'cloudflare',
      ),
    ];
    for (final buildCase in cases) {
      final errors = StringBuffer();
      final code = await runOdroe(
        <String>[
          'build',
          '--project',
          project.path,
          '--server-target',
          buildCase.target,
          '--server-artifact',
          buildCase.artifact,
          '--prerender-output',
          buildCase.output,
        ],
        output: StringBuffer(),
        errors: errors,
      );

      expect(code, 64, reason: '$buildCase');
      expect(
        errors.toString(),
        '--server-artifact and --prerender-output must not overlap.\n',
        reason: '$buildCase',
      );
      for (final output in outputs) {
        expect(output.existsSync(), isFalse, reason: '$buildCase');
      }
    }
  });

  test(
    'artifact-free document build prerenders the explicit website manifest',
    () async {
      final project = Directory('sites/odroe.dev').absolute;
      final artifactDirectory = Directory(
        p.join(project.path, 'build', 'odroe', 'artifact-free-test'),
      );
      final web = Directory('${project.path}/build/cloudflare-prerender-test')
        ..createSync(recursive: true);
      final stale = File('${web.path}/stale.txt')..writeAsStringSync('replace');
      addTearDown(() async {
        if (artifactDirectory.existsSync()) {
          await artifactDirectory.delete(recursive: true);
        }
        if (web.existsSync()) await web.delete(recursive: true);
      });

      final build = await _runDart(<String>[
        'run',
        'odroe',
        'build',
        '--project',
        project.path,
        '--no-server',
        '--server-artifact',
        'build/odroe/artifact-free-test/server',
        '--prerender-output',
        'build/cloudflare-prerender-test',
      ]);
      final logs = '${build.stdout}\n${build.stderr}';

      expect(build.exitCode, 0, reason: logs);
      expect(build.stdout, isNot(contains('prerender-server')));
      expect(build.stdout, isNot(contains('.odroe-staging-')));
      expect(build.stdout, isNot(contains('Built Cloudflare Worker')));
      expect(artifactDirectory.existsSync(), isFalse);
      expect(stale.existsSync(), isFalse);
      final notFound = await File('${web.path}/404.html').readAsString();
      expect(notFound, contains('This route ends here.'));
      final html = await web
          .list(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('.html'))
          .cast<File>()
          .toList();
      final relativeHtml =
          html
              .map(
                (file) => p.posix.joinAll(
                  p.split(p.relative(file.path, from: web.path)),
                ),
              )
              .toList()
            ..sort();
      final sourceSitemap = await File(
        p.join(project.path, 'public', 'sitemap.xml'),
      ).readAsString();
      final expectedHtml =
          RegExp(r'<loc>([^<]+)</loc>')
              .allMatches(sourceSitemap)
              .map((match) => Uri.parse(match.group(1)!).path)
              .map(
                (path) => path == '/'
                    ? 'index.html'
                    : '${path.substring(1)}/index.html',
              )
              .toList()
            ..add('404.html')
            ..sort();
      expect(relativeHtml, expectedHtml);
      expect(
        build.stdout,
        contains('Prerendered ${expectedHtml.length} routes.'),
      );
      for (final asset in <String>['_redirects', 'robots.txt', 'sitemap.xml']) {
        final source = File(p.join(project.path, 'public', asset));
        final built = File(p.join(web.path, asset));
        expect(
          await built.readAsBytes(),
          orderedEquals(await source.readAsBytes()),
          reason: asset,
        );
      }

      final canonicalUrls = <String>[];
      for (final file in html) {
        final relative = p.posix.joinAll(
          p.split(p.relative(file.path, from: web.path)),
        );
        final matches = _canonicalHref.allMatches(await file.readAsString());
        if (relative == '404.html') {
          expect(matches, isEmpty, reason: relative);
        } else {
          expect(matches, hasLength(1), reason: relative);
          canonicalUrls.add(matches.single.group(1)!);
        }
      }
      canonicalUrls.sort();
      final builtSitemap = await File(
        p.join(web.path, 'sitemap.xml'),
      ).readAsString();
      final sitemapUrls =
          RegExp(
              r'<loc>([^<]+)</loc>',
            ).allMatches(builtSitemap).map((match) => match.group(1)!).toList()
            ..sort();
      expect(sitemapUrls.toSet(), hasLength(sitemapUrls.length));
      expect(sitemapUrls, canonicalUrls);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'prerender ignores same-path HTML from public',
    () async {
      final project = await _createDocumentFixture();
      addTearDown(() => project.delete(recursive: true));

      final build = await _runDart(<String>[
        'run',
        'odroe',
        'build',
        '--project',
        project.path,
        '--server-target',
        'cloudflare',
        '--no-server',
      ]);
      final logs = '${build.stdout}\n${build.stderr}';

      expect(build.exitCode, 0, reason: logs);
      expect(build.stdout, contains('Prerendered 1 routes.'));
      expect(
        Directory(
          p.join(project.path, 'build', 'odroe', 'cloudflare'),
        ).existsSync(),
        isFalse,
      );
      final page = await File(
        p.join(project.path, 'build', 'web', 'index.html'),
      ).readAsString();
      expect(page, contains('fresh route'));
      expect(page, isNot(contains('stale public page')));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('prerender isolates and removes application runtime state', () async {
    final project = await _createDocumentFixture();
    addTearDown(() => project.delete(recursive: true));
    await File(p.join(project.path, 'lib', 'server.dart')).writeAsString(r'''
import 'dart:io';

import 'package:odroe/server.dart';

import 'routes.server.dart' as generated;

Server createServer() {
  final path = Platform.environment['ODROE_SQLITE_PATH'];
  if (path == null || path.isEmpty) {
    throw StateError('ODROE_SQLITE_PATH is required during prerender.');
  }
  File(path).writeAsStringSync('prerender state');
  stderr.writeln('ODROE_TEST_STATE=$path');
  return generated.createServer();
}
''');
    final inheritedState = File(p.join(project.path, 'inherited-app.sqlite3'));

    final build = await _runDart(
      <String>[
        'run',
        'odroe',
        'build',
        '--project',
        project.path,
        '--no-server',
      ],
      environment: <String, String>{
        ...Platform.environment,
        'ODROE_SQLITE_PATH': inheritedState.path,
      },
    );
    final logs = '${build.stdout}\n${build.stderr}';

    expect(build.exitCode, 0, reason: logs);
    expect(inheritedState.existsSync(), isFalse);
    final marker = RegExp(
      r'ODROE_TEST_STATE=([^\r\n]+)',
    ).firstMatch(build.stderr);
    expect(marker, isNotNull, reason: logs);
    final isolatedPath = marker!.group(1)!;
    expect(p.equals(isolatedPath, inheritedState.path), isFalse);
    expect(File(isolatedPath).existsSync(), isFalse);
    expect(Directory(p.dirname(isolatedPath)).existsSync(), isFalse);
  });

  test(
    'failed artifact-free prerender preserves the previous website output',
    () async {
      final project = Directory('sites/odroe.dev').absolute;
      final web = Directory(
        '${project.path}/build/cloudflare-prerender-failure-test',
      )..createSync(recursive: true);
      final sentinel = File('${web.path}/sentinel.txt')
        ..writeAsStringSync('keep');
      addTearDown(() async {
        if (web.existsSync()) await web.delete(recursive: true);
      });

      final build = await _runDart(<String>[
        'run',
        'odroe',
        'build',
        '--project',
        project.path,
        '--no-server',
        '--prerender-output',
        'build/cloudflare-prerender-failure-test',
        '--prerender-max-response-bytes',
        '1',
      ]);
      final logs = '${build.stdout}\n${build.stderr}';

      expect(build.exitCode, 1, reason: logs);
      expect(logs, contains('exceeds the 1 byte prerender limit'));
      expect(sentinel.readAsStringSync(), 'keep');
      expect(
        web.listSync().map((entity) => entity.uri.pathSegments.last),
        <String>['sentinel.txt'],
      );
      expect(
        web.parent.listSync().where(
          (entity) => entity.uri.pathSegments.last.startsWith(
            '.cloudflare-prerender-failure-test.odroe-staging-',
          ),
        ),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  final wrangler = Platform.environment['ODROE_WRANGLER'];
  test(
    'generated Worker serves requests in local Workerd',
    () async {
      final project = Directory('example/app').absolute;
      final output = Directory(
        '${project.path}/build/odroe/cloudflare-workerd-test',
      );
      addTearDown(() async {
        if (output.existsSync()) await output.delete(recursive: true);
      });

      await _buildWorker(
        project,
        'build/odroe/cloudflare-workerd-test/server.js',
      );

      final worker = File('${output.path}/worker.mjs');
      expect(worker.existsSync(), isTrue);
      final sourceConfig =
          jsonDecode(
                await File(
                  p.join(project.path, 'wrangler.jsonc'),
                ).readAsString(),
              )
              as Map<String, Object?>;
      sourceConfig
        ..remove(r'$schema')
        ..remove('assets')
        ..['name'] = 'odroe-cloudflare-build-test'
        ..['main'] = 'worker.mjs';
      final databases = (sourceConfig['d1_databases']! as List<Object?>)
          .cast<Map<String, Object?>>();
      databases.single['migrations_dir'] = p.relative(
        p.join(project.path, 'migrations'),
        from: output.path,
      );
      expect(sourceConfig['compatibility_date'], '2026-08-01');
      expect(sourceConfig['compatibility_flags'], <String>[
        'enable_request_signal',
      ]);
      expect(databases.single['binding'], 'DB');
      final config = File('${output.path}/wrangler.json');
      await config.writeAsString(jsonEncode(sourceConfig));

      final runtime = await Directory.systemTemp.createTemp(
        'odroe-cloudflare-workerd-',
      );
      addTearDown(() async {
        if (runtime.existsSync()) await runtime.delete(recursive: true);
      });
      final xdgConfig = await Directory('${runtime.path}/xdg').create();
      final persistence = await Directory('${runtime.path}/state').create();
      final wranglerEnvironment = <String, String>{
        'CI': 'true',
        'NO_COLOR': '1',
        'WRANGLER_SEND_METRICS': 'false',
        'WRANGLER_LOG_PATH': '${runtime.path}/wrangler.log',
        'XDG_CONFIG_HOME': xdgConfig.path,
      };
      final migration = await Process.run(
        wrangler!,
        <String>[
          'd1',
          'migrations',
          'apply',
          'DB',
          '--local',
          '--config',
          config.path,
          '--persist-to',
          persistence.path,
        ],
        workingDirectory: output.path,
        environment: wranglerEnvironment,
        includeParentEnvironment: true,
      ).timeout(const Duration(seconds: 30));
      expect(
        migration.exitCode,
        0,
        reason: '${migration.stdout}\n${migration.stderr}',
      );
      final port = await _unusedPort();
      var inspectorPort = await _unusedPort();
      while (inspectorPort == port) {
        inspectorPort = await _unusedPort();
      }

      final process = await Process.start(
        wrangler,
        <String>[
          'dev',
          '--config',
          config.path,
          '--local',
          '--ip',
          '127.0.0.1',
          '--port',
          '$port',
          '--inspector-port',
          '$inspectorPort',
          '--persist-to',
          persistence.path,
          '--log-level',
          'warn',
          '--show-interactive-dev-session=false',
        ],
        workingDirectory: output.path,
        environment: wranglerEnvironment,
        includeParentEnvironment: true,
      );
      final logs = StringBuffer();
      final stdout = process.stdout.transform(utf8.decoder).listen(logs.write);
      final stderr = process.stderr.transform(utf8.decoder).listen(logs.write);
      int? processExitCode;
      final exitCode = process.exitCode.then((code) {
        processExitCode = code;
        return code;
      });
      addTearDown(() async {
        try {
          await _terminate(process, exitCode);
        } finally {
          await stdout.cancel();
          await stderr.cancel();
        }
      });

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      addTearDown(() => client.close(force: true));
      final origin = 'http://127.0.0.1:$port';
      final response = await _waitForResponse(
        client,
        Uri.parse('$origin/posts/42?preview=true'),
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(response.statusCode, 200, reason: '${response.body}\n$logs');
      expect(
        response.body,
        contains('"location":"/posts/42?preview=true"'),
        reason: logs.toString(),
      );

      final rpcHeaders = <String, String>{
        'origin': origin,
        'x-odroe-server-function': 'true',
      };
      final listFunction = Uri.encodeComponent('posts.list');
      final list = await _waitForResponse(
        client,
        Uri.parse('$origin/__odroe/functions/$listFunction').replace(
          queryParameters: <String, String>{
            'payload': jsonEncode(<String, Object?>{'data': 'newest'}),
          },
        ),
        headers: rpcHeaders,
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(list.statusCode, 200, reason: '${list.body}\n$logs');
      expect(jsonDecode(list.body), <String, Object?>{
        'version': 1,
        'type': 'data',
        'data': <Object?>[
          <String, Object?>{'id': 42, 'title': 'D1 post 42'},
        ],
      });

      final createFunction = Uri.encodeComponent('posts.create');
      final created = await _waitForResponse(
        client,
        Uri.parse('$origin/__odroe/functions/$createFunction'),
        method: 'POST',
        headers: <String, String>{
          ...rpcHeaders,
          'content-type': 'application/json; charset=utf-8',
        },
        requestBody: jsonEncode(<String, Object?>{
          'data': <String, Object?>{'title': '  Created on D1  '},
        }),
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(created.statusCode, 200, reason: '${created.body}\n$logs');
      final createdFrame = jsonDecode(created.body) as Map<String, Object?>;
      expect(createdFrame['version'], 1);
      expect(createdFrame['type'], 'data');
      final createdPost = createdFrame['data']! as Map<String, Object?>;
      expect(createdPost['id'], isA<int>());
      expect(createdPost['id'], isNot(42));
      expect(createdPost['title'], 'Created on D1');

      final function = Uri.encodeComponent('posts.read');
      final post = await _waitForResponse(
        client,
        Uri.parse('$origin/__odroe/functions/$function').replace(
          queryParameters: <String, String>{
            'payload': jsonEncode(<String, Object?>{'data': createdPost['id']}),
          },
        ),
        headers: rpcHeaders,
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(post.statusCode, 200, reason: '${post.body}\n$logs');
      expect(jsonDecode(post.body), <String, Object?>{
        'version': 1,
        'type': 'data',
        'data': createdPost,
      });

      final refreshed = await _waitForResponse(
        client,
        Uri.parse('$origin/__odroe/functions/$listFunction').replace(
          queryParameters: <String, String>{
            'payload': jsonEncode(<String, Object?>{'data': 'newest'}),
          },
        ),
        headers: rpcHeaders,
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(refreshed.statusCode, 200, reason: '${refreshed.body}\n$logs');
      final refreshedFrame = jsonDecode(refreshed.body) as Map<String, Object?>;
      final refreshedPosts = refreshedFrame['data']! as List<Object?>;
      expect(refreshedPosts, contains(equals(createdPost)));

      final rejected = await _waitForResponse(
        client,
        Uri.parse('$origin/__odroe/functions/$createFunction'),
        method: 'POST',
        headers: <String, String>{
          ...rpcHeaders,
          'content-type': 'application/json; charset=utf-8',
        },
        requestBody: jsonEncode(<String, Object?>{
          'data': <String, Object?>{'title': '   '},
        }),
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(rejected.statusCode, 400, reason: '${rejected.body}\n$logs');
      expect(jsonDecode(rejected.body), containsPair('type', 'error'));
      expect(
        jsonDecode(rejected.body),
        containsPair('message', 'Post title is required.'),
      );

      final malformed = await _waitForResponse(
        client,
        Uri.parse('$origin/__odroe/functions/$createFunction'),
        method: 'POST',
        headers: <String, String>{
          ...rpcHeaders,
          'content-type': 'application/json; charset=utf-8',
        },
        requestBody: jsonEncode(<String, Object?>{'data': <String, Object?>{}}),
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(malformed.statusCode, 400, reason: '${malformed.body}\n$logs');
      final malformedFrame = jsonDecode(malformed.body);
      expect(malformedFrame, containsPair('version', 1));
      expect(malformedFrame, containsPair('type', 'error'));
      expect(
        malformedFrame,
        containsPair('message', 'Invalid server function payload.'),
      );

      final afterRejected = await _waitForResponse(
        client,
        Uri.parse('$origin/__odroe/functions/$listFunction').replace(
          queryParameters: <String, String>{
            'payload': jsonEncode(<String, Object?>{'data': 'newest'}),
          },
        ),
        headers: rpcHeaders,
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(afterRejected.statusCode, 200);
      expect(
        (jsonDecode(afterRejected.body) as Map<String, Object?>)['data'],
        refreshedPosts,
      );

      final extraSegment = await _waitForResponse(
        client,
        Uri.parse('$origin/__odroe/functions/$function/extra').replace(
          queryParameters: <String, String>{
            'payload': jsonEncode(<String, Object?>{'data': 42}),
          },
        ),
        headers: rpcHeaders,
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(
        extraSegment.statusCode,
        404,
        reason: '${extraSegment.body}\n$logs',
      );
      expect(jsonDecode(extraSegment.body), containsPair('type', 'notFound'));

      final missing = await _waitForResponse(
        client,
        Uri.parse('$origin/__odroe/functions/$function').replace(
          queryParameters: <String, String>{
            'payload': jsonEncode(<String, Object?>{'data': 404}),
          },
        ),
        headers: rpcHeaders,
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(missing.statusCode, 404, reason: '${missing.body}\n$logs');
      final missingFrame = jsonDecode(missing.body) as Map<String, Object?>;
      expect(missingFrame['version'], 1);
      expect(missingFrame['type'], 'notFound');
      expect(missingFrame['message'], 'Post not found.');
      expect(missingFrame['errorType'], isA<String>());
    },
    skip: wrangler == null || wrangler.isEmpty
        ? 'Set ODROE_WRANGLER to run the local Workerd integration test.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<Directory> _createDocumentFixture() async {
  final project = await Directory.systemTemp.createTemp(
    'odroe-prerender-fixture-',
  );
  try {
    final root = Directory.current.absolute;
    await File(p.join(project.path, 'pubspec.yaml')).writeAsString('''
name: odroe_prerender_fixture
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  odroe:
    path: ${jsonEncode(root.path)}
''');
    final routes = Directory(p.join(project.path, 'lib', 'routes'));
    await routes.create(recursive: true);
    await File(p.join(routes.path, 'route.dart')).writeAsString(r'''
import 'package:odroe/document.dart';
import 'package:odroe/router.dart';

final route = AppRoute<NoParams, NoSearch, NoData>().document(
  (_) => const RouteDocument(
    title: 'Fresh route',
    body: HtmlElement(
      'main',
      children: <HtmlNode>[HtmlText('fresh route')],
    ),
  ),
);
''');
    final public = Directory(p.join(project.path, 'public'));
    await public.create();
    await File(
      p.join(public.path, 'index.html'),
    ).writeAsString('stale public page');

    final config =
        jsonDecode(
              await File(
                p.join(root.path, '.dart_tool', 'package_config.json'),
              ).readAsString(),
            )
            as Map<String, Object?>;
    final packages = (config['packages']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final odroe = packages.singleWhere((package) => package['name'] == 'odroe');
    odroe['rootUri'] = root.uri.toString();
    packages.add(<String, Object?>{
      'name': 'odroe_prerender_fixture',
      'rootUri': project.uri.toString(),
      'packageUri': 'lib/',
      'languageVersion': '3.10',
    });
    final dartTool = Directory(p.join(project.path, '.dart_tool'));
    await dartTool.create();
    await File(
      p.join(dartTool.path, 'package_config.json'),
    ).writeAsString(jsonEncode(config));
    return project;
  } on Object {
    await project.delete(recursive: true);
    rethrow;
  }
}

Future<void> _buildWorker(Directory project, String artifact) async {
  final build = await _runDart(<String>[
    'run',
    'odroe',
    'build',
    '--project',
    project.path,
    '--server-only',
    '--server-target',
    'cloudflare',
    '--server-artifact',
    artifact,
  ]);
  expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
}

Future<ProcessResult> _runDart(
  List<String> arguments, {
  Map<String, String>? environment,
}) => withDartCommandLock(
  () => runTestProcess(
    dartExecutable,
    arguments,
    timeout: const Duration(minutes: 2),
    environment: environment,
  ),
);

Future<int> _unusedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<({int statusCode, String body})> _waitForResponse(
  HttpClient client,
  Uri uri, {
  String method = 'GET',
  Map<String, String> headers = const <String, String>{},
  String? requestBody,
  required int? Function() processExitCode,
  required StringBuffer logs,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    final code = processExitCode();
    if (code != null) {
      throw StateError('Wrangler exited with code $code.\n$logs');
    }
    try {
      final request = await (switch (method) {
        'GET' => client.getUrl(uri),
        'POST' => client.postUrl(uri),
        _ => throw ArgumentError.value(method, 'method'),
      }).timeout(const Duration(seconds: 2));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (requestBody != null) request.add(utf8.encode(requestBody));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2));
      return (statusCode: response.statusCode, body: body);
    } on Object catch (error) {
      lastError = error;
      if (method != 'GET') rethrow;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Wrangler did not become ready: $lastError\n$logs');
}

Future<void> _terminate(Process process, Future<int> exitCode) async {
  await terminateTestProcess(process, exitCode);
}

extension on String {
  String quote() => "'${replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
}

final _canonicalHref = RegExp(r'<link rel="canonical" href="([^"]+)">');
