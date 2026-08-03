import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/database_sqlite.dart';
import 'package:odroe/src/cli/build.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/dart_command_lock.dart';
import '../support/process.dart';

void main() {
  test(
    'native full-stack bundle is complete, atomic, and self-locating',
    () async {
      final project = Directory('example/app').absolute;
      final artifact = Directory(
        p.join(
          project.path,
          'build',
          'odroe',
          'native-static-$pid-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      final webOutputs = Directory(
        p.join(
          project.path,
          'build',
          'odroe',
          'native-web-$pid-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      final flutterOutput = Directory(p.join(webOutputs.path, 'flutter'));
      final prerenderOutput = Directory(p.join(webOutputs.path, 'prerender'));
      final deployment = await Directory.systemTemp.createTemp(
        'odroe-native-static-',
      );
      addTearDown(() async {
        if (artifact.existsSync()) {
          await artifact.delete(recursive: true);
        }
        if (webOutputs.existsSync()) {
          await webOutputs.delete(recursive: true);
        }
        if (deployment.existsSync()) {
          await deployment.delete(recursive: true);
        }
      });

      final artifactPath = p.relative(artifact.path, from: project.path);
      final flutterOutputPath = p.relative(
        flutterOutput.path,
        from: project.path,
      );
      final prerenderOutputPath = p.relative(
        prerenderOutput.path,
        from: project.path,
      );
      final stalePrerender =
          File(p.join(prerenderOutput.path, 'removed-route', 'index.html'))
            ..createSync(recursive: true)
            ..writeAsStringSync('stale prerender');
      final staleFlutter = File(p.join(flutterOutput.path, 'removed-client.js'))
        ..createSync(recursive: true)
        ..writeAsStringSync('stale client');
      final build = await withDartCommandLock(
        () => runTestProcess(dartExecutable, <String>[
          'run',
          'odroe',
          'build',
          '--project',
          project.path,
          '--server-artifact',
          artifactPath,
          '--prerender-output',
          prerenderOutputPath,
          '--',
          'web',
          '--output',
          flutterOutputPath,
        ], timeout: const Duration(minutes: 4)),
      );
      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
      expect(build.stdout, contains('Bundled 2 SQLite migrations'));
      expect(artifact.existsSync(), isTrue);
      final executable = File(
        p.join(artifact.path, 'bin', _testNativeExecutableName),
      );
      expect(executable.existsSync(), isTrue);
      final nativeAssets = Directory(p.join(artifact.path, 'lib'));
      expect(nativeAssets.existsSync(), isTrue);
      expect(nativeAssets.listSync().whereType<File>(), isNotEmpty);
      final bundledMigrations = Directory(p.join(artifact.path, 'migrations'));
      final owner = File(p.join(artifact.path, '.odroe-native-bundle'));
      expect(owner.readAsStringSync(), 'odroe-native-bundle-v1\n');
      for (final name in <String>['0001_posts.sql', '0002_unify_posts.sql']) {
        final source = File(p.join(project.path, 'migrations', name));
        final bundled = File(p.join(bundledMigrations.path, name));
        expect(bundled.readAsBytesSync(), source.readAsBytesSync());
      }
      final bundledWeb = Directory(p.join(artifact.path, 'build', 'web'));
      final routeFile = File(
        p.join(bundledWeb.path, 'posts', '42', 'index.html'),
      );
      final flutterBootstrap = File(
        p.join(bundledWeb.path, 'flutter_bootstrap.js'),
      );
      final flutterMain = File(p.join(bundledWeb.path, 'main.dart.js'));
      expect(routeFile.readAsStringSync(), contains('Odroe Router'));
      expect(flutterBootstrap.lengthSync(), greaterThan(0));
      expect(flutterMain.lengthSync(), greaterThan(0));
      expect(stalePrerender.existsSync(), isFalse);
      expect(staleFlutter.existsSync(), isFalse);
      expect(
        File(
          p.join(bundledWeb.path, 'removed-route', 'index.html'),
        ).existsSync(),
        isFalse,
      );

      final sentinel = File(p.join(artifact.path, 'release-sentinel'))
        ..writeAsStringSync('last known good');
      final failedBuild = await withDartCommandLock(
        () => runTestProcess(dartExecutable, <String>[
          'run',
          'odroe',
          'build',
          '--project',
          project.path,
          '--server-artifact',
          artifactPath,
          '--prerender-output',
          prerenderOutputPath,
          '--',
          'web',
          '--output',
          flutterOutputPath,
          '--odroe-invalid-flutter-option',
        ], timeout: const Duration(minutes: 2)),
      );
      expect(
        failedBuild.exitCode,
        isNot(0),
        reason: '${failedBuild.stdout}\n${failedBuild.stderr}',
      );
      expect(
        '${failedBuild.stdout}\n${failedBuild.stderr}',
        contains('odroe-invalid-flutter-option'),
      );
      expect(artifact.existsSync(), isTrue);
      expect(owner.readAsStringSync(), 'odroe-native-bundle-v1\n');
      expect(sentinel.readAsStringSync(), 'last known good');
      expect(routeFile.readAsStringSync(), contains('Odroe Router'));
      expect(flutterBootstrap.lengthSync(), greaterThan(0));
      expect(flutterMain.lengthSync(), greaterThan(0));

      final withoutPrerender = await withDartCommandLock(
        () => runTestProcess(dartExecutable, <String>[
          'run',
          'odroe',
          'build',
          '--project',
          project.path,
          '--server-artifact',
          artifactPath,
          '--no-prerender',
          '--prerender-output',
          prerenderOutputPath,
          '--',
          'web',
          '--output',
          flutterOutputPath,
        ], timeout: const Duration(minutes: 4)),
      );
      expect(
        withoutPrerender.exitCode,
        0,
        reason: '${withoutPrerender.stdout}\n${withoutPrerender.stderr}',
      );
      expect(routeFile.existsSync(), isFalse);
      expect(
        File(
          p.join(prerenderOutput.path, 'posts', '42', 'index.html'),
        ).existsSync(),
        isTrue,
      );
      expect(flutterBootstrap.lengthSync(), greaterThan(0));
      expect(flutterMain.lengthSync(), greaterThan(0));
      final deployedBundle = Directory(p.join(deployment.path, 'server'));
      artifact.renameSync(deployedBundle.path);
      expect(artifact.existsSync(), isFalse);
      final launchDirectory = Directory(p.join(deployment.path, 'launch'))
        ..createSync();
      final deployedOwner = File(
        p.join(deployedBundle.path, '.odroe-native-bundle'),
      );
      final deployedArtifact = File(
        p.join(deployedBundle.path, 'bin', _testNativeExecutableName),
      );
      expect(deployedArtifact.existsSync(), isTrue);

      final databasePath = p.join(deployedBundle.path, '.odroe', 'app.sqlite3');
      final port = await _unusedPort();
      final firstServer = await _startNativeServer(
        deployedArtifact,
        launchDirectory,
        port: port,
      );
      addTearDown(firstServer.close);
      final logs = firstServer.logs;

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      addTearDown(() => client.close(force: true));
      final html = await _get(
        client,
        Uri.parse('http://127.0.0.1:$port/posts/42'),
        accept: 'text/html',
        logs: logs,
      );
      expect(html.status, HttpStatus.ok, reason: logs.toString());
      expect(html.body, contains('Odroe Router'));
      expect(html.vary, 'Accept');
      final bootstrap = await _get(
        client,
        Uri.parse('http://127.0.0.1:$port/flutter_bootstrap.js'),
        accept: '*/*',
        logs: logs,
      );
      expect(bootstrap.status, HttpStatus.ok, reason: logs.toString());
      expect(bootstrap.body, isNotEmpty);
      expect(bootstrap.contentType, contains('javascript'));

      final json = await _get(
        client,
        Uri.parse('http://127.0.0.1:$port/posts/42?preview=true'),
        accept: 'application/json',
        logs: logs,
      );
      expect(json.status, HttpStatus.ok, reason: logs.toString());
      expect(
        json.body,
        contains('"location":"/posts/42?preview=true"'),
        reason: logs.toString(),
      );
      expect(json.contentType, contains('application/json'));
      expect(json.vary, 'Accept');

      final origin = 'http://127.0.0.1:$port';
      final rpcHeaders = <String, String>{
        'origin': origin,
        'x-odroe-server-function': 'true',
      };
      final listFunction = Uri.encodeComponent('posts.list');
      final list = await _get(
        client,
        Uri.parse('$origin/__odroe/functions/$listFunction').replace(
          queryParameters: <String, String>{
            'payload': jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'cursor': null,
                'ids': <int>[42],
                'limit': 20,
                'sort': 'newest',
              },
            }),
          },
        ),
        accept: 'application/json',
        headers: rpcHeaders,
        logs: logs,
      );
      expect(list.status, HttpStatus.ok, reason: '${list.body}\n$logs');
      expect(jsonDecode(list.body), <String, Object?>{
        'version': 1,
        'type': 'data',
        'data': <String, Object?>{
          'items': <Object?>[
            <String, Object?>{'id': 42, 'title': 'Odroe post 42'},
          ],
          'nextCursor': null,
        },
      });

      final invalidSort = await _get(
        client,
        Uri.parse('$origin/__odroe/functions/$listFunction').replace(
          queryParameters: <String, String>{
            'payload': jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'cursor': null,
                'ids': const <int>[],
                'limit': 20,
                'sort': 'popular',
              },
            }),
          },
        ),
        accept: 'application/json',
        headers: rpcHeaders,
        logs: logs,
      );
      expect(
        invalidSort.status,
        HttpStatus.badRequest,
        reason: '${invalidSort.body}\n$logs',
      );
      expect(jsonDecode(invalidSort.body), containsPair('type', 'error'));
      expect(
        jsonDecode(invalidSort.body),
        containsPair('message', 'Invalid server function payload.'),
      );

      final function = Uri.encodeComponent('posts.read');
      final post = await _get(
        client,
        Uri.parse(
          '$origin/__odroe/functions/$function'
          '?payload=%7B%22data%22%3A42%7D',
        ),
        accept: 'application/json',
        headers: rpcHeaders,
        logs: logs,
      );
      expect(post.status, HttpStatus.ok, reason: '${post.body}\n$logs');
      expect(jsonDecode(post.body), <String, Object?>{
        'version': 1,
        'type': 'data',
        'data': <String, Object?>{'id': 42, 'title': 'Odroe post 42'},
      });
      if (Platform.isMacOS) {
        final bundledSqlite = File(
          p.join(deployedBundle.path, 'lib', 'libsqlite3.dylib'),
        ).resolveSymbolicLinksSync();
        expect(logs.toString(), contains(bundledSqlite));
      }

      final missing = await _get(
        client,
        Uri.parse(
          '$origin/__odroe/functions/$function'
          '?payload=%7B%22data%22%3A404%7D',
        ),
        accept: 'application/json',
        headers: rpcHeaders,
        logs: logs,
      );
      expect(
        missing.status,
        HttpStatus.notFound,
        reason: '${missing.body}\n$logs',
      );
      expect(jsonDecode(missing.body), <String, Object?>{
        'version': 1,
        'type': 'notFound',
        'message': 'Post not found.',
        'errorType': 'NotFound',
      });

      client.close(force: true);
      await firstServer.close();
      expect(File(databasePath).existsSync(), isTrue);
      final database = SqliteDatabase.open(databasePath);
      try {
        final history = await database.query(
          BoundSql.raw('SELECT name FROM _odroe_migrations ORDER BY version'),
          (row) => row.read(0, sqlText),
        );
        expect(history, <String>['0001_posts.sql', '0002_unify_posts.sql']);
        final indexes = await database.query(
          BoundSql.raw(
            "SELECT count(*) FROM sqlite_master WHERE name = 'posts_title'",
          ),
          (row) => row.read(0, sqlInt),
        );
        expect(indexes.single, 1);
        await database.execute(
          BoundSql.raw(
            "UPDATE posts SET title = 'Persisted post 42' WHERE id = 42",
            dialect: SqlDialect.sqlite,
          ),
        );
      } finally {
        await database.close();
      }

      final secondPort = await _unusedPort();
      final secondServer = await _startNativeServer(
        deployedArtifact,
        launchDirectory,
        port: secondPort,
      );
      addTearDown(secondServer.close);
      final secondClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      addTearDown(() => secondClient.close(force: true));
      final secondOrigin = 'http://127.0.0.1:$secondPort';
      final persisted = await _get(
        secondClient,
        Uri.parse(
          '$secondOrigin/__odroe/functions/$function'
          '?payload=%7B%22data%22%3A42%7D',
        ),
        accept: 'application/json',
        headers: <String, String>{
          'origin': secondOrigin,
          'x-odroe-server-function': 'true',
        },
        logs: secondServer.logs,
      );
      expect(
        persisted.status,
        HttpStatus.ok,
        reason: '${persisted.body}\n${secondServer.logs}',
      );
      expect(jsonDecode(persisted.body), <String, Object?>{
        'version': 1,
        'type': 'data',
        'data': <String, Object?>{'id': 42, 'title': 'Persisted post 42'},
      }, reason: secondServer.logs.toString());

      secondClient.close(force: true);
      await secondServer.close();
      final overrideMigrations = Directory(
        p.join(deployedBundle.path, 'schema-history'),
      );
      Directory(
        p.join(deployedBundle.path, 'migrations'),
      ).renameSync(overrideMigrations.path);
      final overridePort = await _unusedPort();
      final overrideServer = await _startNativeServer(
        deployedArtifact,
        launchDirectory,
        port: overridePort,
        databasePath: p.join(deployedBundle.path, '.odroe', 'override.sqlite3'),
        migrationsPath: overrideMigrations.path,
      );
      addTearDown(overrideServer.close);
      final overrideClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      addTearDown(() => overrideClient.close(force: true));
      final overrideOrigin = 'http://127.0.0.1:$overridePort';
      final overridden = await _get(
        overrideClient,
        Uri.parse(
          '$overrideOrigin/__odroe/functions/$function'
          '?payload=%7B%22data%22%3A42%7D',
        ),
        accept: 'application/json',
        headers: <String, String>{
          'origin': overrideOrigin,
          'x-odroe-server-function': 'true',
        },
        logs: overrideServer.logs,
      );
      expect(
        overridden.status,
        HttpStatus.ok,
        reason: overrideServer.logs.toString(),
      );
      expect(jsonDecode(overridden.body), <String, Object?>{
        'version': 1,
        'type': 'data',
        'data': <String, Object?>{'id': 42, 'title': 'Odroe post 42'},
      });

      overrideClient.close(force: true);
      await overrideServer.close();
      Future<ProcessResult> runRejectedBundle() async => runTestProcess(
        deployedArtifact.path,
        const <String>[],
        workingDirectory: launchDirectory.path,
        environment: _nativeServerEnvironment(port: await _unusedPort()),
        includeParentEnvironment: false,
        timeout: const Duration(seconds: 10),
      );

      deployedOwner.writeAsStringSync('not-an-odroe-bundle\n', flush: true);
      var invalidMarker = await runRejectedBundle();
      expect(invalidMarker.exitCode, isNot(0));
      expect(
        '${invalidMarker.stdout}\n${invalidMarker.stderr}',
        contains('Invalid Odroe Native bundle marker.'),
      );
      deployedOwner.deleteSync();
      invalidMarker = await runRejectedBundle();
      expect(invalidMarker.exitCode, isNot(0));
      expect(
        '${invalidMarker.stdout}\n${invalidMarker.stderr}',
        contains('Odroe Native bundle marker is missing or invalid.'),
      );
      Directory(deployedOwner.path).createSync();
      invalidMarker = await runRejectedBundle();
      expect(invalidMarker.exitCode, isNot(0));
      expect(
        '${invalidMarker.stdout}\n${invalidMarker.stderr}',
        contains('Odroe Native bundle marker is missing or invalid.'),
      );
      Directory(deployedOwner.path).deleteSync();
      if (!Platform.isWindows) {
        final markerTarget = File(p.join(deployedBundle.path, 'marker-target'))
          ..writeAsStringSync('odroe-native-bundle-v1\n');
        Link(deployedOwner.path).createSync(markerTarget.path);
        invalidMarker = await runRejectedBundle();
        expect(invalidMarker.exitCode, isNot(0));
        expect(
          '${invalidMarker.stdout}\n${invalidMarker.stderr}',
          contains('Odroe Native bundle marker is missing or invalid.'),
        );
        Link(deployedOwner.path).deleteSync();
        markerTarget.deleteSync();
      }
      expect(
        Directory(p.join(launchDirectory.path, '.odroe')).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(launchDirectory.path, 'build')).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(launchDirectory.path, 'migrations')).existsSync(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('shared Flutter and prerender output replaces stale files', () async {
    final project = Directory('example/app').absolute;
    final output = Directory(
      p.join(
        project.path,
        'build',
        'odroe',
        'shared-web-$pid-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final stale = File(p.join(output.path, 'removed-route', 'index.html'))
      ..createSync(recursive: true)
      ..writeAsStringSync('stale');
    addTearDown(() async {
      if (output.existsSync()) await output.delete(recursive: true);
    });
    final relativeOutput = p.relative(output.path, from: project.path);

    final build = await withDartCommandLock(
      () => runTestProcess(dartExecutable, <String>[
        'run',
        'odroe',
        'build',
        '--project',
        project.path,
        '--no-server',
        '--prerender-output',
        relativeOutput,
        '--',
        'web',
        '--output',
        relativeOutput,
      ], timeout: const Duration(minutes: 3)),
    );

    expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
    expect(stale.existsSync(), isFalse);
    expect(File(p.join(output.path, 'main.dart.js')).existsSync(), isTrue);
    expect(
      File(p.join(output.path, 'posts', '42', 'index.html')).existsSync(),
      isTrue,
    );
  });

  test(
    'native build rejects a linked bundle output without touching its target',
    () async {
      final project = Directory('example/app').absolute;
      final artifact = Directory(
        p.join(
          project.path,
          'build',
          'odroe',
          'native-linked-$pid-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      artifact.parent.createSync(recursive: true);
      final outside = await Directory.systemTemp.createTemp(
        'odroe-native-linked-',
      );
      final sentinel = File(p.join(outside.path, 'sentinel'))
        ..writeAsStringSync('keep');
      final bundleLink = Link(artifact.path)..createSync(outside.path);
      addTearDown(() async {
        if (bundleLink.existsSync()) bundleLink.deleteSync();
        if (outside.existsSync()) await outside.delete(recursive: true);
      });

      final build = await withDartCommandLock(
        () => runTestProcess(dartExecutable, <String>[
          'run',
          'odroe',
          'build',
          '--project',
          project.path,
          '--server-only',
          '--server-artifact',
          p.relative(artifact.path, from: project.path),
          '--sqlite-migrations',
          'migrations',
        ], timeout: const Duration(seconds: 30)),
      );

      expect(build.exitCode, 64, reason: '${build.stdout}\n${build.stderr}');
      expect(build.stderr, contains('cannot traverse a symbolic link'));
      expect(sentinel.readAsStringSync(), 'keep');
      expect(bundleLink.existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: Platform.isWindows
        ? 'Symbolic link permissions vary on Windows.'
        : false,
  );

  test(
    'native build ignores an isolated unselected provider migration directory',
    () async {
      final project = Directory('sites/odroe.dev').absolute;
      final fixture = _nativeBuildFixture(project, 'provider');
      final providerMigration = File(
        p.join(fixture.migrationSource.path, 'V1__postgres.sql'),
      )..writeAsStringSync('SELECT PostgreSQL syntax;');
      addTearDown(() async {
        if (fixture.root.existsSync()) {
          await fixture.root.delete(recursive: true);
        }
      });

      final build = await withDartCommandLock(
        () => runTestProcess(dartExecutable, <String>[
          'run',
          'odroe',
          'build',
          '--project',
          project.path,
          '--server-only',
          '--server-artifact',
          p.relative(fixture.artifact.path, from: project.path),
        ], timeout: const Duration(minutes: 2)),
      );

      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
      expect(build.stdout, isNot(contains('Bundled')));
      expect(fixture.artifact.existsSync(), isTrue);
      expect(providerMigration.readAsStringSync(), 'SELECT PostgreSQL syntax;');
      expect(
        Directory(p.join(fixture.artifact.path, 'migrations')).existsSync(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'native build CLI selection overrides odroe.yaml',
    () async {
      final project = Directory('example/app').absolute;
      final fixture = _nativeBuildFixture(project, 'config-override');
      File(
        p.join(fixture.migrationSource.path, '0001_override.sql'),
      ).writeAsStringSync('SELECT 1;');
      _writeTestBundle(fixture.artifact, 'old server');
      File(p.join(fixture.artifact.path, 'build', 'web', 'stale.html'))
        ..createSync(recursive: true)
        ..writeAsStringSync('stale client');
      addTearDown(() async {
        if (fixture.root.existsSync()) {
          await fixture.root.delete(recursive: true);
        }
      });

      final build = await withDartCommandLock(
        () => runTestProcess(dartExecutable, <String>[
          'run',
          'odroe',
          'build',
          '--project',
          project.path,
          '--server-only',
          '--server-artifact',
          p.relative(fixture.artifact.path, from: project.path),
          '--sqlite-migrations',
          p.relative(fixture.migrationSource.path, from: project.path),
          '--',
          'web',
          '--output',
          'build/web',
        ], timeout: const Duration(minutes: 2)),
      );

      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
      expect(build.stdout, contains('Bundled 1 SQLite migrations'));
      expect(
        Directory(
          p.join(fixture.artifact.path, 'migrations'),
        ).listSync().map((entry) => p.basename(entry.path)).toList(),
        <String>['0001_override.sql'],
      );
      expect(
        Directory(p.join(fixture.artifact.path, 'build', 'web')).existsSync(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('native build refuses to drop a previously selected history', () async {
    final project = Directory('sites/odroe.dev').absolute;
    final fixture = _nativeBuildFixture(project, 'selected-history');
    _writeTestBundle(fixture.artifact, 'old server');
    File(p.join(fixture.artifact.path, 'migrations', '0001_selected.sql'))
      ..createSync(recursive: true)
      ..writeAsStringSync('SELECT 1;');
    addTearDown(() async {
      if (fixture.root.existsSync()) {
        await fixture.root.delete(recursive: true);
      }
    });

    final build = await withDartCommandLock(
      () => runTestProcess(dartExecutable, <String>[
        'run',
        'odroe',
        'build',
        '--project',
        project.path,
        '--server-only',
        '--server-artifact',
        p.relative(fixture.artifact.path, from: project.path),
      ], timeout: const Duration(seconds: 30)),
    );

    expect(build.exitCode, 1, reason: '${build.stdout}\n${build.stderr}');
    expect(build.stderr, contains('previous Native build bundled'));
    expect(
      File(
        p.join(fixture.artifact.path, 'bin', _testNativeExecutableName),
      ).readAsStringSync(),
      'old server',
    );
  });

  test(
    'native build preserves an unowned bundle output',
    () async {
      final project = Directory('example/app').absolute;
      final fixture = _nativeBuildFixture(project, 'unowned');
      File(
        p.join(fixture.migrationSource.path, '0001_records.sql'),
      ).writeAsStringSync('CREATE TABLE records (id INTEGER PRIMARY KEY);');
      fixture.artifact.createSync();
      final sentinel = File(p.join(fixture.artifact.path, 'sentinel'))
        ..writeAsStringSync('keep');
      addTearDown(() async {
        if (fixture.root.existsSync()) {
          await fixture.root.delete(recursive: true);
        }
      });

      final build = await withDartCommandLock(
        () => runTestProcess(dartExecutable, <String>[
          'run',
          'odroe',
          'build',
          '--project',
          project.path,
          '--server-only',
          '--server-artifact',
          p.relative(fixture.artifact.path, from: project.path),
          '--sqlite-migrations',
          p.relative(fixture.migrationSource.path, from: project.path),
        ], timeout: const Duration(seconds: 30)),
      );

      expect(build.exitCode, 1, reason: '${build.stdout}\n${build.stderr}');
      expect(build.stderr, contains('Odroe-owned bundle directory'));
      expect(sentinel.readAsStringSync(), 'keep');
      expect(fixture.artifact.existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('native bundle replacement restores the previous bundle', () async {
    final state = await Directory.systemTemp.createTemp(
      'odroe-native-replace-',
    );
    addTearDown(() => state.delete(recursive: true));
    final output = Directory(p.join(state.path, 'output'))..createSync();
    final bundle = Directory(p.join(output.path, 'server'));
    _writeTestBundle(bundle, 'old server');
    final sentinel = File(p.join(bundle.path, 'sentinel'))
      ..writeAsStringSync('keep');
    final stagedBundle = Directory(p.join(bundle.path, 'staged'));
    _writeTestBundle(stagedBundle, 'new server');

    await expectLater(
      replaceNativeBundle(
        stagedBundle: stagedBundle,
        bundle: bundle,
        lockFile: File(p.join(state.path, 'native-build.lock')),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      File(
        p.join(bundle.path, 'bin', _testNativeExecutableName),
      ).readAsStringSync(),
      'old server',
    );
    expect(sentinel.readAsStringSync(), 'keep');
    expect(stagedBundle.existsSync(), isTrue);
    expect(
      output.listSync().where(
        (entity) => p.basename(entity.path).startsWith('.odroe-'),
      ),
      isEmpty,
    );
  });

  test('native bundle preserves an unowned output', () async {
    final state = Directory.systemTemp.createTempSync('odroe-native-unowned-');
    addTearDown(() => state.deleteSync(recursive: true));
    final output = Directory(p.join(state.path, 'output'))..createSync();
    final bundle = Directory(p.join(output.path, 'server'))..createSync();
    final sentinel = File(p.join(bundle.path, 'sentinel'))
      ..writeAsStringSync('keep');
    final stagedBundle = Directory(p.join(state.path, 'staging'));
    _writeTestBundle(stagedBundle, 'new server');

    await expectLater(
      replaceNativeBundle(
        stagedBundle: stagedBundle,
        bundle: bundle,
        lockFile: File(p.join(state.path, 'native-build.lock')),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(sentinel.readAsStringSync(), 'keep');
    expect(stagedBundle.existsSync(), isTrue);
  });

  test(
    'native bundle validates again while holding the publication lock',
    () async {
      final state = Directory.systemTemp.createTempSync(
        'odroe-native-validation-',
      );
      addTearDown(() => state.deleteSync(recursive: true));
      final bundle = Directory(p.join(state.path, 'output', 'server'));
      final stagedBundle = Directory(p.join(state.path, 'staging'));
      final lockFile = File(p.join(state.path, 'native-build.lock'));
      _writeTestBundle(bundle, 'old server');
      _writeTestBundle(stagedBundle, 'new server');
      var validations = 0;

      await expectLater(
        replaceNativeBundle(
          stagedBundle: stagedBundle,
          bundle: bundle,
          lockFile: lockFile,
          validateBeforePublish: () {
            validations++;
            throw FileSystemException('migration snapshot changed');
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(validations, 1);
      expect(
        File(
          p.join(bundle.path, 'bin', _testNativeExecutableName),
        ).readAsStringSync(),
        'old server',
      );
      expect(stagedBundle.existsSync(), isTrue);

      await replaceNativeBundle(
        stagedBundle: stagedBundle,
        bundle: bundle,
        lockFile: lockFile,
      );
      expect(
        File(
          p.join(bundle.path, 'bin', _testNativeExecutableName),
        ).readAsStringSync(),
        'new server',
      );
    },
  );

  test('native bundle preserves a legacy executable', () async {
    final state = Directory.systemTemp.createTempSync('odroe-native-legacy-');
    addTearDown(() => state.deleteSync(recursive: true));
    final output = Directory(p.join(state.path, 'output'))..createSync();
    final legacy = File(p.join(output.path, 'server'))
      ..writeAsStringSync('old server');
    final stagedBundle = Directory(p.join(state.path, 'staging'));
    _writeTestBundle(stagedBundle, 'new server');

    await expectLater(
      replaceNativeBundle(
        stagedBundle: stagedBundle,
        bundle: Directory(legacy.path),
        lockFile: File(p.join(state.path, 'native-build.lock')),
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(legacy.readAsStringSync(), 'old server');
    expect(stagedBundle.existsSync(), isTrue);
  });

  test(
    'native bundle serializes competing process publications',
    () async {
      final state = Directory.systemTemp.createTempSync(
        'odroe-native-process-race-',
      );
      addTearDown(() => state.deleteSync(recursive: true));
      final output = Directory(p.join(state.path, 'output'))..createSync();
      _writeTestBundle(Directory(p.join(output.path, 'server')), 'old');
      final readyAbsent = File(p.join(state.path, 'ready-absent'));
      final readySelected = File(p.join(state.path, 'ready-selected'));
      final go = File(p.join(state.path, 'go'));
      final script = p.join(
        Directory.current.absolute.path,
        'test',
        'support',
        'native_bundle_publisher.dart',
      );
      final packageConfig = p.join(
        Directory.current.absolute.path,
        '.dart_tool',
        'package_config.json',
      );
      Future<ProcessResult> publish(String mode, File ready) =>
          Process.run(dartExecutable, <String>[
            '--packages=$packageConfig',
            script,
            state.path,
            mode,
            ready.path,
            go.path,
          ], workingDirectory: Directory.current.absolute.path);

      final results = await withDartCommandLock(() async {
        final absent = publish('absent', readyAbsent);
        final selected = publish('selected', readySelected);
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (!readyAbsent.existsSync() || !readySelected.existsSync()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Native publication processes did not reach the barrier.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        go.writeAsStringSync('go');
        return Future.wait(<Future<ProcessResult>>[absent, selected]);
      });

      for (final result in results) {
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }
      expect(
        File(
          p.join(output.path, 'server', 'bin', _testNativeExecutableName),
        ).readAsStringSync(),
        'selected',
      );
      final migrations = Directory(p.join(output.path, 'server', 'migrations'));
      expect(
        File(p.join(migrations.path, '0001_selected.sql')).readAsStringSync(),
        'SELECT 1;',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test('native bundle rejects a migration snapshot changed during compile', () {
    final source = Directory.systemTemp.createTempSync(
      'odroe-native-snapshot-',
    );
    addTearDown(() => source.deleteSync(recursive: true));
    final file = File(p.join(source.path, '0001_records.sql'))
      ..writeAsStringSync('CREATE TABLE records (id INTEGER);');
    final expected = readSqliteMigrations(source.path);
    file.writeAsStringSync('${file.readAsStringSync()}\nCREATE INDEX changed;');

    expect(
      () => verifySqliteMigrationSnapshot(source, expected),
      throwsA(isA<FileSystemException>()),
    );
  });
}

void _writeTestBundle(Directory bundle, String executable) {
  File(p.join(bundle.path, 'bin', _testNativeExecutableName))
    ..createSync(recursive: true)
    ..writeAsStringSync(executable);
  Directory(p.join(bundle.path, 'lib')).createSync();
  File(
    p.join(bundle.path, '.odroe-native-bundle'),
  ).writeAsStringSync('odroe-native-bundle-v1\n');
}

String get _testNativeExecutableName =>
    Platform.isWindows ? 'server.exe' : 'server';

({Directory artifact, Directory migrationSource, Directory root})
_nativeBuildFixture(Directory project, String name) {
  final root = Directory(
    p.join(
      project.path,
      'build',
      'odroe',
      'native-$name-$pid-${DateTime.now().microsecondsSinceEpoch}',
    ),
  )..createSync(recursive: true);
  final migrationSource = Directory(p.join(root.path, 'source-migrations'))
    ..createSync();
  return (
    artifact: Directory(p.join(root.path, 'server')),
    migrationSource: migrationSource,
    root: root,
  );
}

Future<int> _unusedPort() async {
  final reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = reservation.port;
  await reservation.close();
  return port;
}

Future<_NativeServerProcess> _startNativeServer(
  File artifact,
  Directory launchDirectory, {
  required int port,
  String? databasePath,
  String? migrationsPath,
}) async {
  final process = await Process.start(
    artifact.path,
    const <String>[],
    workingDirectory: launchDirectory.path,
    environment: _nativeServerEnvironment(
      port: port,
      databasePath: databasePath,
      migrationsPath: migrationsPath,
    ),
    includeParentEnvironment: false,
  );
  return _NativeServerProcess(process);
}

Map<String, String> _nativeServerEnvironment({
  required int port,
  String? databasePath,
  String? migrationsPath,
}) {
  final environment = <String, String>{
    for (final entry in Platform.environment.entries)
      if (entry.key != 'ODROE_SQLITE_PATH' &&
          entry.key != 'ODROE_MIGRATIONS_PATH' &&
          entry.key != 'ODROE_WEB_ROOT' &&
          entry.key != 'ODROE_FLUTTER_ORIGIN_FILE')
        entry.key: entry.value,
    'ODROE_HOST': '127.0.0.1',
    'ODROE_PORT': '$port',
    if (Platform.isMacOS) 'DYLD_PRINT_LIBRARIES': '1',
    'ODROE_SQLITE_PATH': ?databasePath,
    'ODROE_MIGRATIONS_PATH': ?migrationsPath,
  };
  return environment;
}

final class _NativeServerProcess {
  _NativeServerProcess(this.process) {
    _stdout = process.stdout.transform(utf8.decoder).listen(logs.write);
    _stderr = process.stderr.transform(utf8.decoder).listen(logs.write);
  }

  final Process process;
  final StringBuffer logs = StringBuffer();
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    } finally {
      await _stdout.cancel();
      await _stderr.cancel();
    }
  }
}

Future<({int status, String body, String? contentType, String? vary})> _get(
  HttpClient client,
  Uri uri, {
  required String accept,
  Map<String, String> headers = const <String, String>{},
  required StringBuffer logs,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, accept);
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await request.close();
      return (
        status: response.statusCode,
        body: await response.transform(utf8.decoder).join(),
        contentType: response.headers.value(HttpHeaders.contentTypeHeader),
        vary: response.headers.value(HttpHeaders.varyHeader),
      );
    } on SocketException catch (error) {
      lastError = error;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  throw StateError('Native server did not start: $lastError\n$logs');
}
