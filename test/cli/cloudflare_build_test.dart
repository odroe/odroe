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
      final javaScript = await server.readAsString();
      expect(javaScript, isNot(matches(RegExp(r'\beval\s*\('))));
      expect(javaScript, isNot(matches(RegExp(r'\bnew\s+Function\s*\('))));
      expect(await server.length(), lessThan(500 * 1024));

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
  {},
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
    'Cloudflare document build prerenders the explicit website manifest',
    () async {
      final project = Directory('sites/odroe.dev').absolute;
      final artifactDirectory = Directory(
        '${project.path}/build/odroe/cloudflare-prerender-test',
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
        '--server-target',
        'cloudflare',
        '--server-artifact',
        'build/odroe/cloudflare-prerender-test/server.js',
        '--prerender-output',
        'build/cloudflare-prerender-test',
      ]);
      final logs = '${build.stdout}\n${build.stderr}';

      expect(build.exitCode, 0, reason: logs);
      expect(build.stdout, contains('Prerendered 11 routes.'));
      expect(build.stdout, isNot(contains('prerender-server')));
      expect(build.stdout, isNot(contains('.odroe-staging-')));
      expect(File('${artifactDirectory.path}/server.js').existsSync(), isTrue);
      expect(File('${artifactDirectory.path}/worker.mjs').existsSync(), isTrue);
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
      expect(relativeHtml, <String>[
        '404.html',
        'docs/core/app/index.html',
        'docs/core/query/index.html',
        'docs/core/routing/index.html',
        'docs/data/database/index.html',
        'docs/deploy/index.html',
        'docs/getting-started/index.html',
        'docs/index.html',
        'docs/server/index.html',
        'docs/web/document/index.html',
        'index.html',
      ]);
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
      ]);
      final logs = '${build.stdout}\n${build.stderr}';

      expect(build.exitCode, 0, reason: logs);
      expect(build.stdout, contains('Prerendered 1 routes.'));
      final page = await File(
        p.join(project.path, 'build', 'web', 'index.html'),
      ).readAsString();
      expect(page, contains('fresh route'));
      expect(page, isNot(contains('stale public page')));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'failed Cloudflare prerender preserves the previous website output',
    () async {
      final project = Directory('sites/odroe.dev').absolute;
      final artifactDirectory = Directory(
        '${project.path}/build/odroe/cloudflare-prerender-failure-test',
      );
      final web = Directory(
        '${project.path}/build/cloudflare-prerender-failure-test',
      )..createSync(recursive: true);
      final sentinel = File('${web.path}/sentinel.txt')
        ..writeAsStringSync('keep');
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
        '--server-target',
        'cloudflare',
        '--server-artifact',
        'build/odroe/cloudflare-prerender-failure-test/server.js',
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
      final config = File('${output.path}/wrangler.json');
      await config.writeAsString(
        jsonEncode(<String, Object>{
          'name': 'odroe-cloudflare-build-test',
          'main': 'worker.mjs',
          'compatibility_date': '2026-07-29',
        }),
      );

      final runtime = await Directory.systemTemp.createTemp(
        'odroe-cloudflare-workerd-',
      );
      addTearDown(() async {
        if (runtime.existsSync()) await runtime.delete(recursive: true);
      });
      final xdgConfig = await Directory('${runtime.path}/xdg').create();
      final persistence = await Directory('${runtime.path}/state').create();
      final port = await _unusedPort();
      var inspectorPort = await _unusedPort();
      while (inspectorPort == port) {
        inspectorPort = await _unusedPort();
      }

      final process = await Process.start(
        wrangler!,
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
        environment: <String, String>{
          'CI': 'true',
          'NO_COLOR': '1',
          'WRANGLER_SEND_METRICS': 'false',
          'WRANGLER_LOG_PATH': '${runtime.path}/wrangler.log',
          'XDG_CONFIG_HOME': xdgConfig.path,
        },
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
      final response = await _waitForResponse(
        client,
        Uri.parse('http://127.0.0.1:$port/posts/42?preview=true'),
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(response.statusCode, 200, reason: '${response.body}\n$logs');
      expect(
        response.body,
        contains('"location":"/posts/42?preview=true"'),
        reason: logs.toString(),
      );
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

Future<ProcessResult> _runDart(List<String> arguments) => withDartCommandLock(
  () => runTestProcess(
    dartExecutable,
    arguments,
    timeout: const Duration(minutes: 2),
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
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 2));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
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
