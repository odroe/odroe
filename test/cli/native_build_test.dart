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
    'native artifact serves SQLite RPC and routes outside the source tree',
    () async {
      final project = Directory('example/app').absolute;
      final artifactDirectory = Directory(
        p.join(
          project.path,
          'build',
          'odroe',
          'native-static-$pid-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      final artifact = File(p.join(artifactDirectory.path, 'server'));
      final deployment = await Directory.systemTemp.createTemp(
        'odroe-native-static-',
      );
      addTearDown(() async {
        if (artifactDirectory.existsSync()) {
          await artifactDirectory.delete(recursive: true);
        }
        if (deployment.existsSync()) {
          await deployment.delete(recursive: true);
        }
      });
      final routeFile = File(
        p.join(deployment.path, 'build', 'web', 'posts', '42', 'index.html'),
      );
      await routeFile.parent.create(recursive: true);
      await routeFile.writeAsString('static native artifact');

      final artifactPath = p.relative(artifact.path, from: project.path);
      final build = await withDartCommandLock(
        () => runTestProcess(dartExecutable, <String>[
          'run',
          'odroe',
          'build',
          '--project',
          project.path,
          '--server-only',
          '--server-artifact',
          artifactPath,
          '--sqlite-migrations',
          'migrations',
        ], timeout: const Duration(minutes: 2)),
      );
      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
      expect(build.stdout, contains('Bundled 2 SQLite migrations'));
      expect(artifact.existsSync(), isTrue);
      final bundledMigrations = Directory(
        p.join(artifactDirectory.path, 'migrations'),
      );
      final owner = File(
        p.join(bundledMigrations.path, '.odroe-native-migrations'),
      );
      expect(owner.readAsStringSync(), 'server\n');
      for (final name in <String>['0001_posts.sql', '0002_unify_posts.sql']) {
        final source = File(p.join(project.path, 'migrations', name));
        final bundled = File(p.join(bundledMigrations.path, name));
        expect(bundled.readAsBytesSync(), source.readAsBytesSync());
        final deployed = File(p.join(deployment.path, 'migrations', name));
        deployed.parent.createSync(recursive: true);
        bundled.copySync(deployed.path);
      }
      final staleBuild = await withDartCommandLock(
        () => runTestProcess(dartExecutable, <String>[
          'run',
          'odroe',
          'build',
          '--project',
          project.path,
          '--server-only',
          '--server-artifact',
          artifactPath,
        ], timeout: const Duration(seconds: 30)),
      );
      expect(
        staleBuild.exitCode,
        1,
        reason: '${staleBuild.stdout}\n${staleBuild.stderr}',
      );
      expect(
        staleBuild.stderr,
        contains('Pass --sqlite-migrations again or remove the sidecar'),
      );
      expect(artifact.existsSync(), isTrue);
      expect(owner.readAsStringSync(), 'server\n');
      final deployedArtifact = File(p.join(deployment.path, 'server'));
      artifact.renameSync(deployedArtifact.path);
      expect(artifact.existsSync(), isFalse);
      expect(deployedArtifact.existsSync(), isTrue);

      final databasePath = p.join(deployment.path, '.odroe', 'app.sqlite3');
      final port = await _unusedPort();
      final firstServer = await _startNativeServer(
        deployedArtifact,
        deployment,
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
      expect(html.body, 'static native artifact');
      expect(html.vary, 'Accept');

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
      final function = Uri.encodeComponent('posts.read');
      final post = await _get(
        client,
        Uri.parse(
          '$origin/__odroe/functions/$function'
          '?payload=%7B%22data%22%3A42%7D',
        ),
        accept: 'application/json',
        headers: <String, String>{
          'origin': origin,
          'x-odroe-server-function': 'true',
        },
        logs: logs,
      );
      expect(post.status, HttpStatus.ok, reason: '${post.body}\n$logs');
      expect(jsonDecode(post.body), <String, Object?>{
        'version': 1,
        'type': 'data',
        'data': <String, Object?>{'id': 42, 'title': 'Odroe post 42'},
      });

      final missing = await _get(
        client,
        Uri.parse(
          '$origin/__odroe/functions/$function'
          '?payload=%7B%22data%22%3A404%7D',
        ),
        accept: 'application/json',
        headers: <String, String>{
          'origin': origin,
          'x-odroe-server-function': 'true',
        },
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
        deployment,
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
        p.join(deployment.path, 'schema-history'),
      );
      Directory(
        p.join(deployment.path, 'migrations'),
      ).renameSync(overrideMigrations.path);
      final overridePort = await _unusedPort();
      final overrideServer = await _startNativeServer(
        deployedArtifact,
        deployment,
        port: overridePort,
        databasePath: p.join(deployment.path, '.odroe', 'override.sqlite3'),
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
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'native build rejects a linked migration output without touching its target',
    () async {
      final project = Directory('example/app').absolute;
      final artifactDirectory = Directory(
        p.join(
          project.path,
          'build',
          'odroe',
          'native-linked-$pid-${DateTime.now().microsecondsSinceEpoch}',
        ),
      )..createSync(recursive: true);
      final outside = await Directory.systemTemp.createTemp(
        'odroe-native-linked-',
      );
      final sentinel = File(p.join(outside.path, 'sentinel'))
        ..writeAsStringSync('keep');
      final migrationLink = Link(p.join(artifactDirectory.path, 'migrations'))
        ..createSync(outside.path);
      addTearDown(() async {
        if (migrationLink.existsSync()) migrationLink.deleteSync();
        if (artifactDirectory.existsSync()) {
          await artifactDirectory.delete(recursive: true);
        }
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
          p.relative(
            p.join(artifactDirectory.path, 'server'),
            from: project.path,
          ),
          '--sqlite-migrations',
          'migrations',
        ], timeout: const Duration(seconds: 30)),
      );

      expect(build.exitCode, 1, reason: '${build.stdout}\n${build.stderr}');
      expect(build.stderr, contains('regular directory'));
      expect(sentinel.readAsStringSync(), 'keep');
      expect(
        File(p.join(artifactDirectory.path, 'server')).existsSync(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: Platform.isWindows
        ? 'Symbolic link permissions vary on Windows.'
        : false,
  );

  test(
    'native build ignores an isolated unselected provider migration directory',
    () async {
      final project = Directory('example/app').absolute;
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
        Directory(p.join(fixture.root.path, 'migrations')).existsSync(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'native build preserves an unowned migration output',
    () async {
      final project = Directory('example/app').absolute;
      final fixture = _nativeBuildFixture(project, 'unowned');
      File(
        p.join(fixture.migrationSource.path, '0001_records.sql'),
      ).writeAsStringSync('CREATE TABLE records (id INTEGER PRIMARY KEY);');
      final output = Directory(p.join(fixture.root.path, 'migrations'))
        ..createSync();
      final sentinel = File(p.join(output.path, 'sentinel'))
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
      expect(build.stderr, contains('is not owned by this server artifact'));
      expect(sentinel.readAsStringSync(), 'keep');
      expect(fixture.artifact.existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('native bundle replacement restores both previous outputs', () async {
    final state = await Directory.systemTemp.createTemp(
      'odroe-native-replace-',
    );
    addTearDown(() => state.delete(recursive: true));
    final output = Directory(p.join(state.path, 'output'))..createSync();
    final staging = Directory(p.join(state.path, 'staging'))..createSync();
    final artifact = File(p.join(output.path, 'server'))
      ..writeAsStringSync('old server');
    final migrations = Directory(p.join(output.path, 'migrations'))
      ..createSync();
    File(
      p.join(migrations.path, '0001_old.sql'),
    ).writeAsStringSync('old migration');
    final stagedArtifact = File(p.join(staging.path, 'server'))
      ..writeAsStringSync('new server');
    final missingStagedMigrations = Directory(
      p.join(staging.path, 'missing-migrations'),
    );

    await expectLater(
      replaceNativeBundle(
        stagedArtifact: stagedArtifact,
        stagedMigrations: missingStagedMigrations,
        artifact: artifact,
        migrations: migrations,
        lockFile: File(p.join(state.path, 'native-build.lock')),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(artifact.readAsStringSync(), 'old server');
    expect(
      File(p.join(migrations.path, '0001_old.sql')).readAsStringSync(),
      'old migration',
    );
    expect(
      output.listSync().where(
        (entity) => p.basename(entity.path).startsWith('.odroe-'),
      ),
      isEmpty,
    );
  });

  test(
    'native bundle restores a sidecar replaced before publication',
    () async {
      final state = Directory.systemTemp.createTempSync(
        'odroe-native-owner-race-',
      );
      addTearDown(() => state.deleteSync(recursive: true));
      final output = Directory(p.join(state.path, 'output'))..createSync();
      final staging = Directory(p.join(state.path, 'staging'))..createSync();
      final artifact = File(p.join(output.path, 'server'))
        ..writeAsStringSync('old server');
      final migrations = Directory(p.join(output.path, 'migrations'))
        ..createSync();
      final sentinel = File(p.join(migrations.path, 'sentinel'))
        ..writeAsStringSync('keep');
      final stagedArtifact = File(p.join(staging.path, 'server'))
        ..writeAsStringSync('new server');
      final stagedMigrations = Directory(p.join(staging.path, 'migrations'))
        ..createSync();
      File(
        p.join(stagedMigrations.path, '.odroe-native-migrations'),
      ).writeAsStringSync('server\n');

      await expectLater(
        replaceNativeBundle(
          stagedArtifact: stagedArtifact,
          stagedMigrations: stagedMigrations,
          artifact: artifact,
          migrations: migrations,
          lockFile: File(p.join(state.path, 'native-build.lock')),
          expectedMigrationOwner: 'server\n',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(artifact.readAsStringSync(), 'old server');
      expect(sentinel.readAsStringSync(), 'keep');
      expect(stagedArtifact.readAsStringSync(), 'new server');
    },
  );

  test(
    'native bundle rejects a sidecar appearing before publication',
    () async {
      final state = Directory.systemTemp.createTempSync(
        'odroe-native-absent-race-',
      );
      addTearDown(() => state.deleteSync(recursive: true));
      final output = Directory(p.join(state.path, 'output'))..createSync();
      final staging = Directory(p.join(state.path, 'staging'))..createSync();
      final artifact = File(p.join(output.path, 'server'))
        ..writeAsStringSync('old server');
      final stagedArtifact = File(p.join(staging.path, 'server'))
        ..writeAsStringSync('new server');
      final migrations = Directory(p.join(output.path, 'migrations'))
        ..createSync();
      final sentinel = File(p.join(migrations.path, 'sentinel'))
        ..writeAsStringSync('keep');

      await expectLater(
        replaceNativeBundle(
          stagedArtifact: stagedArtifact,
          stagedMigrations: null,
          artifact: artifact,
          migrations: migrations,
          lockFile: File(p.join(state.path, 'native-build.lock')),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(artifact.readAsStringSync(), 'old server');
      expect(stagedArtifact.readAsStringSync(), 'new server');
      expect(sentinel.readAsStringSync(), 'keep');
    },
  );

  test(
    'native bundle serializes competing process publications',
    () async {
      final state = Directory.systemTemp.createTempSync(
        'odroe-native-process-race-',
      );
      addTearDown(() => state.deleteSync(recursive: true));
      final output = Directory(p.join(state.path, 'output'))..createSync();
      File(p.join(output.path, 'server')).writeAsStringSync('old');
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
        File(p.join(output.path, 'server')).readAsStringSync(),
        'selected',
      );
      final migrations = Directory(p.join(output.path, 'migrations'));
      expect(
        File(
          p.join(migrations.path, '.odroe-native-migrations'),
        ).readAsStringSync(),
        'server\n',
      );
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

({File artifact, Directory migrationSource, Directory root})
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
    artifact: File(p.join(root.path, 'server')),
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
  Directory workingDirectory, {
  required int port,
  String? databasePath,
  String? migrationsPath,
}) async {
  final environment = <String, String>{
    for (final entry in Platform.environment.entries)
      if (entry.key != 'ODROE_SQLITE_PATH' &&
          entry.key != 'ODROE_MIGRATIONS_PATH')
        entry.key: entry.value,
    'ODROE_HOST': '127.0.0.1',
    'ODROE_PORT': '$port',
    'ODROE_SQLITE_PATH': ?databasePath,
    'ODROE_MIGRATIONS_PATH': ?migrationsPath,
  };
  final process = await Process.start(
    artifact.path,
    const <String>[],
    workingDirectory: workingDirectory.path,
    environment: environment,
    includeParentEnvironment: false,
  );
  return _NativeServerProcess(process);
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
