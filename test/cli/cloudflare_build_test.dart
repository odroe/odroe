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
const prepared = [];
const database = {
  prepare(sql) {
    const call = {sql, parameters: null, rawCalls: 0};
    prepared.push(call);
    const statement = {
      bind(...parameters) {
        call.parameters = parameters;
        return statement;
      },
      raw(options) {
        if (options?.columnNames !== true) {
          throw new Error('expected D1 column names');
        }
        call.rawCalls++;
        return Promise.resolve([
          ['id', 'title'],
          [42, 'D1 post 42'],
        ]);
      },
    };
    return statement;
  },
};
const environment = {DB: database};
const context = {waitUntil() {}};
const response = await worker.fetch(
  new Request('https://example.test/posts/42?preview=true', {
    headers: {accept: 'application/json'},
  }),
  environment,
  context,
);
if (response.status !== 200) throw new Error(`status \${response.status}`);
const body = await response.text();
if (!body.includes('"location":"/posts/42?preview=true"')) {
  throw new Error(body);
}

async function listPosts(sort) {
  const url = new URL(
    'https://example.test/__odroe/functions/' +
      encodeURIComponent('posts.list'),
  );
  url.searchParams.set('payload', JSON.stringify({
    data: {cursor: null, ids: [42], limit: 1, sort},
  }));
  return worker.fetch(
    new Request(url, {
      headers: {
        origin: url.origin,
        'x-odroe-server-function': 'true',
      },
    }),
    environment,
    context,
  );
}

const valid = await listPosts('newest');
if (valid.status !== 200) throw new Error(await valid.text());
const validBody = await valid.json();
if (
  validBody.type !== 'data' ||
  validBody.data.items.length !== 1 ||
  validBody.data.items[0].id !== 42 ||
  validBody.data.items[0].title !== 'D1 post 42' ||
  validBody.data.nextCursor !== null
) {
  throw new Error(JSON.stringify(validBody));
}
if (
  prepared.length !== 1 ||
  prepared[0].parameters?.length !== 1 ||
  prepared[0].parameters[0] !== 42 ||
  prepared[0].rawCalls !== 1
) {
  throw new Error(JSON.stringify(prepared));
}

const prepareCount = prepared.length;
const invalid = await listPosts('popular');
const invalidBody = await invalid.text();
if (
  invalid.status !== 400 ||
  !invalidBody.includes('Invalid server function payload.')
) {
  throw new Error(`status \${invalid.status}: \${invalidBody}`);
}
if (prepared.length !== prepareCount) {
  throw new Error('invalid enum input reached D1');
}
''',
      ], timeout: const Duration(seconds: 30));
      expect(smoke.exitCode, 0, reason: '${smoke.stdout}\n${smoke.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('Cloudflare-only build ignores configured Native history', () async {
    final project = await _createDocumentFixture();
    addTearDown(() => project.delete(recursive: true));
    File(
      p.join(project.path, 'odroe.yaml'),
    ).writeAsStringSync('sqlite_migrations: missing\n');

    await _buildWorker(project, 'build/odroe/cloudflare/server.js');

    expect(
      File(
        p.join(project.path, 'build', 'odroe', 'cloudflare', 'server.js'),
      ).existsSync(),
      isTrue,
    );
  });

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
      Directory(p.join(project.path, 'build', 'native-bundle')),
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

    final cases =
        <({String artifact, String output, String target, bool migrations})>[
          (
            artifact: 'build/overlap-test/server',
            output: 'build/overlap-test',
            target: 'native',
            migrations: false,
          ),
          (
            artifact: 'build/overlap-test/server.js',
            output: 'build/overlap-test',
            target: 'cloudflare',
            migrations: false,
          ),
          (
            artifact: 'build/native-bundle/server',
            output: 'build/native-bundle/server/migrations',
            target: 'native',
            migrations: false,
          ),
          (
            artifact: 'build/Overlap-Case/server.js',
            output: 'build/overlap-case',
            target: 'cloudflare',
            migrations: false,
          ),
          (
            artifact: 'build/cloudflare-sidecar/server.js',
            output: 'build/cloudflare-sidecar/worker.mjs',
            target: 'cloudflare',
            migrations: false,
          ),
          (
            artifact: 'build/cloudflare-deps/server.js',
            output: 'build/cloudflare-deps/server.js.deps',
            target: 'cloudflare',
            migrations: false,
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
          if (buildCase.migrations) ...<String>[
            '--sqlite-migrations',
            'content',
          ],
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

  test('migration source cannot overlap prerender output', () async {
    final project = Directory('sites/odroe.dev').absolute;
    final state = Directory(
      p.join(
        project.path,
        'build',
        'migration-overlap-$pid-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (state.existsSync()) state.deleteSync(recursive: true);
    });
    final cases = <({Directory source, Directory output})>[
      (
        source: Directory(p.join(state.path, 'output', 'migrations')),
        output: Directory(p.join(state.path, 'output')),
      ),
      (
        source: Directory(p.join(state.path, 'source')),
        output: Directory(p.join(state.path, 'source', 'web')),
      ),
    ];

    for (final buildCase in cases) {
      buildCase.source.createSync(recursive: true);
      final migration = File(p.join(buildCase.source.path, '0001_probe.sql'))
        ..writeAsStringSync('CREATE TABLE probe (id INTEGER PRIMARY KEY);');
      final errors = StringBuffer();

      final code = await runOdroe(
        <String>[
          'build',
          '--project',
          project.path,
          '--no-server',
          '--sqlite-migrations',
          p.relative(buildCase.source.path, from: project.path),
          '--prerender-output',
          p.relative(buildCase.output.path, from: project.path),
        ],
        output: StringBuffer(),
        errors: errors,
      );

      expect(code, 64, reason: '$buildCase');
      expect(
        errors.toString(),
        'SQLite migration source and --prerender-output must not overlap.\n',
        reason: '$buildCase',
      );
      expect(
        migration.readAsStringSync(),
        'CREATE TABLE probe (id INTEGER PRIMARY KEY);',
      );
    }
  });

  test('migration source cannot overlap server outputs', () async {
    final project = Directory('sites/odroe.dev').absolute;
    final state = Directory(
      p.join(
        project.path,
        'build',
        'migration-server-overlap-$pid-'
            '${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (state.existsSync()) state.deleteSync(recursive: true);
    });
    final cases = <({Directory source, String artifact, String target})>[
      (
        source: Directory(p.join(state.path, 'native-source')),
        artifact: p.join(state.path, 'native-source', '0001_probe.sql'),
        target: 'native',
      ),
      (
        source: Directory(p.join(state.path, 'native-bundle', 'migrations')),
        artifact: p.join(state.path, 'native-bundle'),
        target: 'native',
      ),
      (
        source: Directory(p.join(state.path, 'cloudflare', 'worker.mjs')),
        artifact: p.join(state.path, 'cloudflare', 'server.js'),
        target: 'cloudflare',
      ),
      (
        source: Directory(
          p.join(state.path, 'cloudflare-deps', 'server.js.deps'),
        ),
        artifact: p.join(state.path, 'cloudflare-deps', 'server.js'),
        target: 'cloudflare',
      ),
    ];

    for (final buildCase in cases) {
      buildCase.source.createSync(recursive: true);
      final migration = File(p.join(buildCase.source.path, '0001_probe.sql'))
        ..writeAsStringSync('SELECT 1;');
      final errors = StringBuffer();

      final code = await runOdroe(
        <String>[
          'build',
          '--project',
          project.path,
          '--server-target',
          buildCase.target,
          '--server-artifact',
          p.relative(buildCase.artifact, from: project.path),
          '--sqlite-migrations',
          p.relative(buildCase.source.path, from: project.path),
        ],
        output: StringBuffer(),
        errors: errors,
      );

      expect(code, 64, reason: '$buildCase');
      expect(
        errors.toString(),
        'SQLite migration source and server artifact outputs must not overlap.\n',
        reason: '$buildCase',
      );
      expect(migration.readAsStringSync(), 'SELECT 1;');
    }
  });

  test('migration source cannot overlap generated route outputs', () async {
    final project = Directory('sites/odroe.dev').absolute;
    final state = Directory(
      p.join(
        project.path,
        'build',
        'migration-route-overlap-$pid-'
            '${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (state.existsSync()) state.deleteSync(recursive: true);
    });

    for (final option in <String>['--output', '--server-output']) {
      final optionName = option.substring(2);
      final caseRoot = Directory(p.join(state.path, optionName))..createSync();
      final source = Directory(p.join(caseRoot.path, 'migrations'))
        ..createSync();
      final migration = File(p.join(source.path, '0001_probe.sql'))
        ..writeAsStringSync('SELECT 1;');
      final outputs = <String>[
        caseRoot.path,
        migration.path,
        p.join(source.path, 'generated.dart'),
      ];

      for (final output in outputs) {
        final errors = StringBuffer();
        final code = await runOdroe(
          <String>[
            'build',
            '--project',
            project.path,
            '--no-server',
            '--sqlite-migrations',
            p.relative(source.path, from: project.path),
            option,
            p.relative(output, from: project.path),
          ],
          output: StringBuffer(),
          errors: errors,
        );

        expect(code, 64, reason: '$option $output');
        expect(
          errors.toString(),
          'SQLite migration source and generated route outputs must not '
          'overlap.\n',
          reason: '$option $output',
        );
        expect(migration.readAsStringSync(), 'SELECT 1;');
      }
    }
  });

  test('generated route outputs cannot overlap build outputs', () async {
    final project = Directory('sites/odroe.dev').absolute;
    final root = p.join(
      project.path,
      'build',
      'generated-build-overlap-$pid-'
          '${DateTime.now().microsecondsSinceEpoch}',
    );
    final output = Directory(root);
    addTearDown(() {
      if (output.existsSync()) output.deleteSync(recursive: true);
    });

    final cases = <({List<String> arguments, String error})>[
      (
        arguments: <String>[
          '--server-only',
          '--server-artifact',
          p.relative(p.join(root, 'server'), from: project.path),
          '--output',
          p.relative(p.join(root, 'server'), from: project.path),
        ],
        error:
            'Generated route outputs and server artifact outputs must not '
            'overlap.\n',
      ),
      (
        arguments: <String>[
          '--no-server',
          '--prerender-output',
          p.relative(root, from: project.path),
          '--server-output',
          p.relative(p.join(root, 'routes.server.dart'), from: project.path),
        ],
        error:
            'Generated route outputs and --prerender-output must not '
            'overlap.\n',
      ),
    ];

    for (final buildCase in cases) {
      final errors = StringBuffer();
      final code = await runOdroe(
        <String>['build', '--project', project.path, ...buildCase.arguments],
        output: StringBuffer(),
        errors: errors,
      );

      expect(code, 64, reason: '${buildCase.arguments}');
      expect(errors.toString(), buildCase.error);
      expect(output.existsSync(), isFalse);
    }
  });

  test('route source cannot overlap destructive build outputs', () async {
    final project = Directory('sites/odroe.dev').absolute;
    final state = Directory(
      p.join(
        project.path,
        'build',
        'route-build-overlap-$pid-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (state.existsSync()) state.deleteSync(recursive: true);
    });
    final routes = Directory(p.join(state.path, 'output', 'routes'))
      ..createSync(recursive: true);
    final source = File(p.join(routes.path, 'route.dart'))
      ..writeAsStringSync(r'''
import 'package:odroe/document.dart';
import 'package:odroe/router.dart';

final route = AppRoute<NoParams, NoSearch, NoData>().document(
  (_) => const RouteDocument(title: 'Protected route', body: HtmlText('ok')),
);
''');
    final cases = <({List<String> arguments, String error})>[
      (
        arguments: <String>[
          '--no-server',
          '--routes',
          p.relative(routes.path, from: project.path),
          '--prerender-output',
          p.relative(routes.parent.path, from: project.path),
        ],
        error: 'Route source and --prerender-output must not overlap.\n',
      ),
      (
        arguments: <String>[
          '--server-only',
          '--routes',
          p.relative(routes.path, from: project.path),
          '--server-artifact',
          p.relative(p.join(routes.path, 'server'), from: project.path),
        ],
        error: 'Route source and server artifact outputs must not overlap.\n',
      ),
    ];

    for (final buildCase in cases) {
      final errors = StringBuffer();
      final code = await runOdroe(
        <String>['build', '--project', project.path, ...buildCase.arguments],
        output: StringBuffer(),
        errors: errors,
      );

      expect(code, 64, reason: '${buildCase.arguments}');
      expect(errors.toString(), buildCase.error);
      expect(source.readAsStringSync(), contains('Protected route'));
    }
  });

  test(
    'Flutter output cannot overlap Odroe sources or server outputs',
    () async {
      final project = Directory('sites/odroe.dev').absolute;
      final state = Directory(
        p.join(
          project.path,
          'build',
          'flutter-overlap-$pid-${DateTime.now().microsecondsSinceEpoch}',
        ),
      )..createSync(recursive: true);
      addTearDown(() {
        if (state.existsSync()) state.deleteSync(recursive: true);
      });
      final webRoot = Directory(p.join(project.path, 'build', 'web'))
        ..createSync(recursive: true);
      final migrationSource = Directory(p.join(webRoot.path, 'migrations'))
        ..createSync();
      final migration = File(p.join(migrationSource.path, '0001_probe.sql'))
        ..writeAsStringSync('SELECT 1;');
      final routeSource = Directory(p.join(webRoot.path, 'routes'))
        ..createSync();
      final route = File(p.join(routeSource.path, 'route.dart'))
        ..writeAsStringSync(r'''
import 'package:odroe/router.dart';

final route = AppRoute<NoParams, NoSearch, NoData>();
''');
      final linkedOutput = Platform.isWindows
          ? null
          : (Link(p.join(state.path, 'linked-output'))
              ..createSync(routeSource.path));
      addTearDown(() {
        if (webRoot.existsSync()) webRoot.deleteSync(recursive: true);
      });
      final relativeState = p.relative(state.path, from: project.path);
      final cases = <({List<String> arguments, String error})>[
        (
          arguments: <String>[
            '--no-prerender',
            '--server-artifact',
            'build/web/server',
            '--',
            'web',
          ],
          error:
              'Flutter build output and server artifact outputs must not '
              'overlap.\n',
        ),
        (
          arguments: <String>[
            '--no-prerender',
            '--server-artifact',
            '$relativeState/output-dir/server',
            '--',
            'web',
            '--output-dir=$relativeState/output-dir',
          ],
          error:
              'Flutter build output and server artifact outputs must not '
              'overlap.\n',
        ),
        (
          arguments: <String>[
            '--no-prerender',
            '--server-artifact',
            '$relativeState/repeated/server',
            '--',
            'web',
            '--output',
            '$relativeState/safe',
            '--output-dir=$relativeState/repeated',
          ],
          error:
              'Flutter build output and server artifact outputs must not '
              'overlap.\n',
        ),
        (
          arguments: <String>[
            '--no-prerender',
            '--sqlite-migrations',
            p.relative(migrationSource.path, from: project.path),
            '--',
            'web',
          ],
          error:
              'Flutter build output and SQLite migration source must not '
              'overlap.\n',
        ),
        (
          arguments: <String>[
            '--no-server',
            '--no-prerender',
            '--routes',
            p.relative(routeSource.path, from: project.path),
            '--',
            'web',
          ],
          error: 'Flutter build output and route source must not overlap.\n',
        ),
        if (linkedOutput != null)
          (
            arguments: <String>[
              '--no-server',
              '--no-prerender',
              '--routes',
              p.relative(routeSource.path, from: project.path),
              '--',
              'web',
              '--output',
              p.relative(linkedOutput.path, from: project.path),
            ],
            error: 'Flutter build output and route source must not overlap.\n',
          ),
        (
          arguments: <String>[
            '--no-server',
            '--no-prerender',
            '--output',
            'build/web/routes.dart',
            '--',
            'web',
          ],
          error:
              'Flutter build output and generated route outputs must not '
              'overlap.\n',
        ),
        (
          arguments: <String>[
            '--no-prerender',
            '--server-artifact',
            '$relativeState/custom/server',
            '--',
            'web',
            '--output',
            '$relativeState/custom',
          ],
          error:
              'Flutter build output and server artifact outputs must not '
              'overlap.\n',
        ),
        (
          arguments: <String>[
            '--no-prerender',
            '--server-artifact',
            'build/app/server',
            '--',
            'apk',
          ],
          error:
              'Flutter build output and server artifact outputs must not '
              'overlap.\n',
        ),
      ];

      for (final buildCase in cases) {
        final errors = StringBuffer();
        final code = await runOdroe(
          <String>['build', '--project', project.path, ...buildCase.arguments],
          output: StringBuffer(),
          errors: errors,
        );

        expect(code, 64, reason: '${buildCase.arguments}');
        expect(errors.toString(), buildCase.error);
        expect(migration.readAsStringSync(), 'SELECT 1;');
        expect(route.readAsStringSync(), contains('AppRoute'));
      }
    },
  );

  test('Flutter configured build root participates in overlap checks', () async {
    final project = Directory('sites/odroe.dev').absolute;
    final state = await Directory.systemTemp.createTemp(
      'odroe-flutter-build-root-',
    );
    addTearDown(() => state.delete(recursive: true));
    final home = Directory(p.join(state.path, 'home'))..createSync();
    final xdg = Directory(p.join(state.path, 'xdg'))..createSync();
    final settings = Platform.isWindows
        ? File(p.join(home.path, '.flutter_settings'))
        : File(p.join(xdg.path, 'settings'));
    settings.writeAsStringSync(
      jsonEncode(<String, Object?>{'build-dir': 'build/odroe'}),
    );

    final root = Directory.current.absolute;
    final build = await runTestProcess(
      dartExecutable,
      <String>[
        '--packages=${p.join(root.path, '.dart_tool', 'package_config.json')}',
        p.join(root.path, 'bin', 'odroe.dart'),
        'build',
        '--project',
        project.path,
        '--no-prerender',
        '--server-artifact',
        'build/odroe/web/server',
        '--',
        'web',
      ],
      timeout: const Duration(seconds: 30),
      environment: <String, String>{
        ...Platform.environment,
        'HOME': home.path,
        'APPDATA': home.path,
        'XDG_CONFIG_HOME': xdg.path,
      },
    );

    expect(build.exitCode, 64, reason: '${build.stdout}\n${build.stderr}');
    expect(
      build.stderr,
      contains(
        'Flutter build output and server artifact outputs must not overlap.',
      ),
    );
    expect(
      File(
        p.join(project.path, 'build', 'odroe', 'web', 'server'),
      ).existsSync(),
      isFalse,
    );

    if (!Platform.isWindows) {
      final withoutHome = await runTestProcess(
        dartExecutable,
        <String>[
          '--packages=${p.join(root.path, '.dart_tool', 'package_config.json')}',
          p.join(root.path, 'bin', 'odroe.dart'),
          'build',
          '--project',
          project.path,
          '--no-prerender',
          '--server-artifact',
          'build/odroe/web/server',
          '--',
          'web',
        ],
        timeout: const Duration(seconds: 30),
        environment: <String, String>{
          ...Platform.environment,
          'HOME': '',
          'XDG_CONFIG_HOME': xdg.path,
        },
      );

      expect(
        withoutHome.exitCode,
        64,
        reason: '${withoutHome.stdout}\n${withoutHome.stderr}',
      );
      expect(
        withoutHome.stderr,
        contains(
          'Flutter build output and server artifact outputs must not overlap.',
        ),
      );
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
    'prerender manifest imports the current generated route snapshot',
    () async {
      for (final staleSnapshot in <bool>[false, true]) {
        final project = await _createDocumentFixture();
        addTearDown(() => project.delete(recursive: true));
        if (staleSnapshot) {
          final code = await runOdroe(
            <String>['generate', '--project', project.path],
            output: StringBuffer(),
            errors: StringBuffer(),
          );
          expect(code, 0);
        }

        final fresh = File(
          p.join(project.path, 'lib', 'routes', 'fresh', 'route.dart'),
        );
        await fresh.parent.create(recursive: true);
        await fresh.writeAsString(r'''
import 'package:odroe/router.dart';

final route = AppRoute<NoParams, NoSearch, NoData>();
''');
        await File(p.join(project.path, 'lib', 'prerender.dart')).writeAsString(
          r'''
import 'routes.dart' as generated;

Future<Iterable<Uri>> prerenderLocations() async {
  generated.routes.fresh.hashCode;
  return <Uri>[Uri(path: '/')];
}
''',
        );

        final build = await _runDart(<String>[
          'run',
          'odroe',
          'build',
          '--project',
          project.path,
          '--no-server',
        ]);
        final logs = '${build.stdout}\n${build.stderr}';

        expect(build.exitCode, 0, reason: 'stale=$staleSnapshot\n$logs');
        expect(
          await File(
            p.join(project.path, 'build', 'web', 'index.html'),
          ).readAsString(),
          contains('fresh route'),
        );
      }
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
  final migrations = Platform.environment['ODROE_MIGRATIONS_PATH'];
  if (migrations == null || migrations.isEmpty) {
    throw StateError('ODROE_MIGRATIONS_PATH is required during prerender.');
  }
  File(path).writeAsStringSync('prerender state');
  stderr.writeln('ODROE_TEST_STATE=$path');
  stderr.writeln('ODROE_TEST_MIGRATIONS=$migrations');
  return generated.createServer();
}
''');
    final inheritedState = File(p.join(project.path, 'inherited-app.sqlite3'));
    final inheritedMigrations = p.join(project.path, 'inherited-migrations');
    await Directory(p.join(project.path, 'migrations')).create();

    final build = await _runDart(
      <String>[
        'run',
        'odroe',
        'build',
        '--project',
        project.path,
        '--no-server',
        '--sqlite-migrations',
        'migrations',
      ],
      environment: <String, String>{
        ...Platform.environment,
        'ODROE_SQLITE_PATH': inheritedState.path,
        'ODROE_MIGRATIONS_PATH': inheritedMigrations,
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
    final migrationMarker = RegExp(
      r'ODROE_TEST_MIGRATIONS=([^\r\n]+)',
    ).firstMatch(build.stderr);
    expect(migrationMarker, isNotNull, reason: logs);
    expect(
      p.normalize(migrationMarker!.group(1)!),
      p.normalize(p.join(project.path, 'migrations')),
    );
    expect(p.equals(migrationMarker.group(1)!, inheritedMigrations), isFalse);
  });

  test('prerender ignores inherited migrations without selection', () async {
    final project = await _createDocumentFixture();
    addTearDown(() => project.delete(recursive: true));
    await File(p.join(project.path, 'lib', 'server.dart')).writeAsString(r'''
import 'dart:io';

import 'package:odroe/server.dart';

import 'routes.server.dart' as generated;

Server createServer() {
  final migrations = Platform.environment['ODROE_MIGRATIONS_PATH'];
  stderr.writeln('ODROE_TEST_MIGRATIONS=${migrations ?? 'unset'}');
  if (migrations != null) {
    throw StateError('Inherited migrations reached prerender.');
  }
  return generated.createServer();
}
''');

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
        'ODROE_MIGRATIONS_PATH': p.join(project.path, 'inherited-migrations'),
      },
    );
    final logs = '${build.stdout}\n${build.stderr}';

    expect(build.exitCode, 0, reason: logs);
    expect(build.stderr, contains('ODROE_TEST_MIGRATIONS=unset'));
    expect(build.stdout, contains('Prerendered 1 routes.'));
  });

  test(
    'native prerender uses staged migrations and rejects source drift',
    () async {
      final project = await _createDocumentFixture();
      addTearDown(() => project.delete(recursive: true));
      final migrationSource = Directory(p.join(project.path, 'migrations'))
        ..createSync();
      final migration = File(p.join(migrationSource.path, '0001_probe.sql'))
        ..writeAsStringSync('SELECT 1;');
      final marker = File(p.join(project.path, 'selected-migration.txt'));
      await File(p.join(project.path, 'lib', 'server.dart')).writeAsString(r'''
import 'dart:io';

import 'package:odroe/server.dart';

import 'routes.server.dart' as generated;

Server createServer() {
  final selected = Platform.environment['ODROE_MIGRATIONS_PATH'];
  if (selected == null || selected.isEmpty) {
    throw StateError('ODROE_MIGRATIONS_PATH is required during prerender.');
  }
  if (Platform.environment['ODROE_TEST_MUTATE_MIGRATION'] == 'true') {
    File('migrations/0001_probe.sql').writeAsStringSync('SELECT 2;');
  }
  final selectedSql = File(
    '$selected${Platform.pathSeparator}0001_probe.sql',
  ).readAsStringSync();
  File('selected-migration.txt').writeAsStringSync('$selected\n$selectedSql');
  return generated.createServer();
}
''');
      final artifact = Directory(
        p.join(project.path, 'build', 'odroe', 'snapshot', 'server'),
      );

      final build = await _runDart(<String>[
        'run',
        'odroe',
        'build',
        '--project',
        project.path,
        '--server-artifact',
        p.relative(artifact.path, from: project.path),
        '--sqlite-migrations',
        'migrations',
      ]);
      final logs = '${build.stdout}\n${build.stderr}';

      expect(build.exitCode, 0, reason: logs);
      final selected = marker.readAsLinesSync();
      expect(selected.first, contains('.odroe-native-'));
      expect(p.basename(selected.first), 'migrations');
      expect(selected.skip(1).join('\n'), 'SELECT 1;');
      expect(migration.readAsStringSync(), 'SELECT 1;');
      expect(
        File(
          p.join(artifact.path, 'migrations', '0001_probe.sql'),
        ).readAsStringSync(),
        'SELECT 1;',
      );
      final sentinel = File(p.join(artifact.path, 'release-sentinel'))
        ..writeAsStringSync('last known good');
      final webSentinel = File(
        p.join(project.path, 'build', 'web', 'release-sentinel'),
      )..writeAsStringSync('last known client');

      final changed = await _runDart(
        <String>[
          'run',
          'odroe',
          'build',
          '--project',
          project.path,
          '--server-artifact',
          p.relative(artifact.path, from: project.path),
          '--sqlite-migrations',
          'migrations',
        ],
        environment: <String, String>{
          ...Platform.environment,
          'ODROE_TEST_MUTATE_MIGRATION': 'true',
        },
      );
      final changedLogs = '${changed.stdout}\n${changed.stderr}';

      expect(changed.exitCode, 1, reason: changedLogs);
      expect(
        changedLogs,
        contains('SQLite migrations changed while the native server'),
      );
      expect(migration.readAsStringSync(), 'SELECT 2;');
      expect(sentinel.readAsStringSync(), 'last known good');
      expect(webSentinel.readAsStringSync(), 'last known client');
      expect(
        File(
          p.join(artifact.path, 'migrations', '0001_probe.sql'),
        ).readAsStringSync(),
        'SELECT 1;',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

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
    'generated Worker upgrades legacy D1 and serves requests in local Workerd',
    () async {
      final wranglerExecutable = wrangler!;
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
      final migrations = Directory(p.join(output.path, 'migrations'))
        ..createSync();
      File(
        p.join(migrations.path, '0001_posts.sql'),
      ).writeAsStringSync(_legacyPostsMigration);
      databases.single['migrations_dir'] = 'migrations';
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
      Future<ProcessResult> runWrangler(List<String> arguments) => Process.run(
        wranglerExecutable,
        <String>[
          ...arguments,
          '--config',
          config.path,
          '--persist-to',
          persistence.path,
        ],
        workingDirectory: output.path,
        environment: wranglerEnvironment,
        includeParentEnvironment: true,
      ).timeout(const Duration(seconds: 30));

      final legacyMigration = await runWrangler(<String>[
        'd1',
        'migrations',
        'apply',
        'DB',
        '--local',
      ]);
      expect(
        legacyMigration.exitCode,
        0,
        reason: '${legacyMigration.stdout}\n${legacyMigration.stderr}',
      );
      final existingPost = await runWrangler(<String>[
        'd1',
        'execute',
        'DB',
        '--local',
        '--command',
        "INSERT INTO posts (id, title) VALUES (43, 'Existing D1 post')",
      ]);
      expect(
        existingPost.exitCode,
        0,
        reason: '${existingPost.stdout}\n${existingPost.stderr}',
      );

      for (final name in <String>['0001_posts.sql', '0002_unify_posts.sql']) {
        await File(
          p.join(project.path, 'migrations', name),
        ).copy(p.join(migrations.path, name));
      }
      final migration = await runWrangler(<String>[
        'd1',
        'migrations',
        'apply',
        'DB',
        '--local',
      ]);
      expect(
        migration.exitCode,
        0,
        reason: '${migration.stdout}\n${migration.stderr}',
      );
      expect(migration.stdout, contains('0002_unify_posts.sql'));
      final repeatedMigration = await runWrangler(<String>[
        'd1',
        'migrations',
        'apply',
        'DB',
        '--local',
      ]);
      expect(
        repeatedMigration.exitCode,
        0,
        reason: '${repeatedMigration.stdout}\n${repeatedMigration.stderr}',
      );
      expect(repeatedMigration.stdout, contains('No migrations to apply'));
      final port = await _unusedPort();
      var inspectorPort = await _unusedPort();
      while (inspectorPort == port) {
        inspectorPort = await _unusedPort();
      }

      final process = await Process.start(
        wranglerExecutable,
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
            'payload': jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'cursor': null,
                'ids': <int>[42, 43, 404],
                'limit': 1,
                'sort': 'newest',
              },
            }),
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
        'data': <String, Object?>{
          'items': <Object?>[
            <String, Object?>{'id': 43, 'title': 'Existing D1 post'},
          ],
          'nextCursor': 43,
        },
      });

      final nextList = await _waitForResponse(
        client,
        Uri.parse('$origin/__odroe/functions/$listFunction').replace(
          queryParameters: <String, String>{
            'payload': jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'cursor': 43,
                'ids': <int>[42, 43, 404],
                'limit': 1,
                'sort': 'newest',
              },
            }),
          },
        ),
        headers: rpcHeaders,
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(nextList.statusCode, 200, reason: '${nextList.body}\n$logs');
      expect(jsonDecode(nextList.body), <String, Object?>{
        'version': 1,
        'type': 'data',
        'data': <String, Object?>{
          'items': <Object?>[
            <String, Object?>{'id': 42, 'title': 'Odroe post 42'},
          ],
          'nextCursor': null,
        },
      });

      final oversizedList = await _waitForResponse(
        client,
        Uri.parse('$origin/__odroe/functions/$listFunction').replace(
          queryParameters: <String, String>{
            'payload': jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'cursor': null,
                'ids': List<int>.generate(101, (index) => index),
                'limit': 20,
                'sort': 'newest',
              },
            }),
          },
        ),
        headers: rpcHeaders,
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(
        oversizedList.statusCode,
        400,
        reason: '${oversizedList.body}\n$logs',
      );
      expect(
        jsonDecode(oversizedList.body),
        containsPair(
          'message',
          'Post ID filter cannot contain more than 100 values.',
        ),
      );

      final invalidLimit = await _waitForResponse(
        client,
        Uri.parse('$origin/__odroe/functions/$listFunction').replace(
          queryParameters: <String, String>{
            'payload': jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'cursor': null,
                'ids': const <int>[],
                'limit': 51,
                'sort': 'newest',
              },
            }),
          },
        ),
        headers: rpcHeaders,
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(invalidLimit.statusCode, 400, reason: logs.toString());
      expect(
        jsonDecode(invalidLimit.body),
        containsPair('message', 'Post page limit must be between 1 and 50.'),
      );

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
            'payload': jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'cursor': null,
                'ids': const <int>[],
                'limit': 20,
                'sort': 'newest',
              },
            }),
          },
        ),
        headers: rpcHeaders,
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(refreshed.statusCode, 200, reason: '${refreshed.body}\n$logs');
      final refreshedFrame = jsonDecode(refreshed.body) as Map<String, Object?>;
      final refreshedData = refreshedFrame['data']! as Map<String, Object?>;
      final refreshedPosts = refreshedData['items']! as List<Object?>;
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
            'payload': jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'cursor': null,
                'ids': const <int>[],
                'limit': 20,
                'sort': 'newest',
              },
            }),
          },
        ),
        headers: rpcHeaders,
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(afterRejected.statusCode, 200);
      expect(
        ((jsonDecode(afterRejected.body) as Map<String, Object?>)['data']!
            as Map<String, Object?>)['items'],
        refreshedData['items'],
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

const _legacyPostsMigration = '''
CREATE TABLE posts (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL
) STRICT;

INSERT INTO posts (id, title) VALUES (42, 'D1 post 42');
''';

Future<Directory> _createDocumentFixture() async {
  final project = await Directory.systemTemp.createTemp(
    'odroe-prerender-fixture-',
  );
  try {
    final root = Directory.current.absolute;
    // Prerender fixtures exercise Odroe, not sqlite3's network downloader.
    await File(p.join(project.path, 'pubspec.yaml')).writeAsString('''
name: odroe_prerender_fixture
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  odroe:
    path: ${jsonEncode(root.path)}
hooks:
  user_defines:
    sqlite3:
      source: system
      name_windows: winsqlite3
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
