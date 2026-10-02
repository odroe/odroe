@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/database_sqlite.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/dart_command_lock.dart';
import '../support/process.dart';

void main() {
  test('dev rejects an empty inherited migration path', () async {
    final result = await withDartCommandLock(
      () => runTestProcess(
        dartExecutable,
        const <String>[
          'run',
          'odroe',
          'dev',
          '--project',
          'example/app',
          '--server-only',
          '--port',
          '0',
        ],
        environment: <String, String>{
          ...Platform.environment,
          'ODROE_MIGRATIONS_PATH': '',
        },
        timeout: const Duration(seconds: 10),
      ),
    );

    expect(result.exitCode, 64, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('ODROE_MIGRATIONS_PATH must not be empty.'));
  });

  test(
    'native dev reloads nested source changes into real HTTP responses',
    () async {
      await withDartCommandLock(() async {
        final project = await Directory.systemTemp.createTemp(
          'odroe-native-watch-',
        );
        addTearDown(() => project.delete(recursive: true));
        File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: native_watch_fixture
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  odroe:
    path: ${jsonEncode(Directory.current.absolute.path)}
hooks:
  user_defines:
    sqlite3:
      source: system
      name_windows: winsqlite3
''');
        final sharedPage =
            File(p.join(project.path, 'lib', 'shared', 'nested', 'page.dart'))
              ..createSync(recursive: true)
              ..writeAsStringSync("const label = 'native watch one';\n");
        File(p.join(project.path, 'lib', 'routes', 'route.dart'))
          ..createSync(recursive: true)
          ..writeAsStringSync(r'''
import 'package:odroe/document.dart';
import 'package:odroe/router.dart';
import '../shared/nested/page.dart';

final route = AppRoute<NoParams, NoSearch, NoData>().document(
  (_) => const RouteDocument(body: HtmlText(label)),
);
''');
        final pubGet = await runTestProcess(
          'flutter',
          const <String>['pub', 'get', '--offline'],
          workingDirectory: project.path,
          timeout: const Duration(minutes: 1),
        );
        expect(
          pubGet.exitCode,
          0,
          reason: '${pubGet.stdout}\n${pubGet.stderr}',
        );
        final process = await Process.start(dartExecutable, <String>[
          'run',
          'odroe',
          'dev',
          '--project',
          project.path,
          '--server-only',
          '--port',
          '0',
        ]);
        final logs = StringBuffer();
        final stdout = process.stdout
            .transform(utf8.decoder)
            .listen(logs.write);
        final stderr = process.stderr
            .transform(utf8.decoder)
            .listen(logs.write);
        final exitCode = process.exitCode;
        addTearDown(() async {
          await terminateTestProcess(process, exitCode);
          await stdout.cancel();
          await stderr.cancel();
        });
        final client = HttpClient();
        addTearDown(client.close);
        Future<void> waitForBody(String expected) async {
          Object? lastError;
          final deadline = DateTime.now().add(const Duration(seconds: 30));
          while (DateTime.now().isBefore(deadline)) {
            final origin = RegExp(
              r'Odroe listening on (http://[^\s]+)',
            ).allMatches(logs.toString()).lastOrNull;
            if (origin != null) {
              try {
                final request = await client.getUrl(
                  Uri.parse(origin.group(1)!),
                );
                final response = await request.close();
                final body = await response.transform(utf8.decoder).join();
                if (response.statusCode == 200 && body.contains(expected)) {
                  return;
                }
              } on Object catch (error) {
                lastError = error;
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          fail('Native development did not serve $expected. $lastError\n$logs');
        }

        await waitForBody('native watch one');
        sharedPage.writeAsStringSync("const label = 'native watch two';\n");
        await waitForBody('native watch two');
        sharedPage.writeAsStringSync("const label = 'native watch three';\n");
        await waitForBody('native watch three');
      });
    },
  );

  test('dev serves the generated route tree and server functions', () async {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final state = await Directory.systemTemp.createTemp('odroe-cli-state-');
    addTearDown(() async {
      if (state.existsSync()) await state.delete(recursive: true);
    });
    final project = Directory('example/app').absolute;
    final sourceState = Directory(
      p.join(
        project.path,
        '.dart_tool',
        'odroe',
        'dev-cwd-$pid-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final databaseFile = File(p.join(sourceState.path, 'app.sqlite3'));
    final relativeDatabasePath = p.relative(
      databaseFile.path,
      from: project.path,
    );
    addTearDown(() async {
      if (sourceState.existsSync()) {
        await sourceState.delete(recursive: true);
      }
    });

    final migrationsDirectory = Directory(p.join(state.path, 'migrations'))
      ..createSync();
    for (final name in <String>['0001_posts.sql', '0002_unify_posts.sql']) {
      File(
        p.join('example/app', 'migrations', name),
      ).copySync(p.join(migrationsDirectory.path, name));
    }
    final devMigration = File(
      p.join(migrationsDirectory.path, '9999_dev_watch.sql'),
    );
    final dartCommandLock = await acquireDartCommandLock();
    final publicDirectory = Directory('example/app/public').absolute;
    final publicDirectoryExisted = publicDirectory.existsSync();
    final publicAsset = File('${publicDirectory.path}/dev-asset.js');
    final publicAssetExisted = publicAsset.existsSync();
    final publicAssetBytes = publicAssetExisted
        ? publicAsset.readAsBytesSync()
        : null;
    publicDirectory.createSync();
    publicAsset.writeAsStringSync('source public asset');
    addTearDown(() {
      if (publicAssetExisted) {
        publicAsset.writeAsBytesSync(publicAssetBytes!, flush: true);
      } else if (publicAsset.existsSync()) {
        publicAsset.deleteSync();
      }
      if (!publicDirectoryExisted &&
          publicDirectory.existsSync() &&
          publicDirectory.listSync().isEmpty) {
        publicDirectory.deleteSync();
      }
    });
    final stalePage = File(
      'example/app/build/web/posts/42/index.html',
    ).absolute;
    final stalePageExisted = stalePage.existsSync();
    final stalePageBytes = stalePageExisted
        ? stalePage.readAsBytesSync()
        : null;
    final candidateDirectories = <Directory>[
      Directory('example/app/build/web').absolute,
      Directory('example/app/build/web/posts').absolute,
      stalePage.parent,
    ];
    final existingDirectories = <String>{
      for (final directory in candidateDirectories)
        if (directory.existsSync()) directory.path,
    };
    stalePage.parent.createSync(recursive: true);
    stalePage.writeAsStringSync('stale dev build');
    addTearDown(() {
      if (stalePageExisted) {
        stalePage.writeAsBytesSync(stalePageBytes!, flush: true);
      } else if (stalePage.existsSync()) {
        stalePage.deleteSync();
      }
      for (final directory in candidateDirectories.reversed) {
        if (!existingDirectories.contains(directory.path) &&
            directory.existsSync() &&
            directory.listSync().isEmpty) {
          directory.deleteSync();
        }
      }
    });
    late final Process process;
    try {
      process = await Process.start(
        dartExecutable,
        <String>[
          'run',
          'odroe',
          'dev',
          '--project',
          'example/app',
          '--server-only',
          '--port',
          '$port',
        ],
        environment: <String, String>{
          ...Platform.environment,
          'ODROE_FLUTTER_ORIGIN_FILE': '/stale/flutter-origin',
          'ODROE_SQLITE_PATH': relativeDatabasePath,
          'ODROE_MIGRATIONS_PATH': migrationsDirectory.path,
        },
      );
    } on Object {
      await dartCommandLock.release();
      rethrow;
    }
    final output = StringBuffer();
    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .listen(output.write);
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(output.write);
    final stdoutDone = stdoutSubscription.asFuture<void>();
    final stderrDone = stderrSubscription.asFuture<void>();
    addTearDown(() async {
      try {
        await terminateTestProcess(process);
        try {
          await Future.wait<void>(<Future<void>>[
            stdoutDone,
            stderrDone,
          ]).timeout(const Duration(seconds: 5));
        } on TimeoutException {
          await Future.wait<void>(<Future<void>>[
            stdoutSubscription.cancel(),
            stderrSubscription.cancel(),
          ]);
        }
      } finally {
        await dartCommandLock.release();
      }
    });

    final client = HttpClient();
    addTearDown(client.close);
    String? page;
    Object? lastError;
    for (var attempt = 0; attempt < 80; attempt++) {
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/posts/42?preview=true'),
        );
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        page = await response.transform(utf8.decoder).join();
        if (response.statusCode == 200) break;
      } on Object catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(
      page,
      contains('"location":"/posts/42?preview=true"'),
      reason: '$lastError\n$output',
    );
    expect(databaseFile.existsSync(), isTrue);
    final assetRequest = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/dev-asset.js'),
    );
    final assetResponse = await assetRequest.close();
    expect(assetResponse.statusCode, HttpStatus.ok);
    expect(
      await assetResponse.transform(utf8.decoder).join(),
      'source public asset',
    );
    final bootstrap = await File(
      'example/app/.dart_tool/odroe/server.dart',
    ).readAsString();
    final enterBundle = bootstrap.indexOf('_enterNativeBundle(arguments);');
    expect(enterBundle, isNonNegative);
    expect(
      enterBundle,
      lessThan(
        bootstrap.indexOf("final platformPort = Platform.environment['PORT'];"),
      ),
    );
    expect(
      bootstrap,
      contains('final markerType = FileSystemEntity.typeSync('),
    );
    expect(bootstrap, contains('followLinks: false'));
    expect(
      bootstrap,
      contains("const bool.fromEnvironment('dart.vm.product')"),
    );
    expect(bootstrap, contains("'--odroe-internal-prerender'"));
    expect(bootstrap, contains("'odroe-native-bundle-v1\\n'"));
    expect(
      bootstrap,
      contains(
        "Platform.environment['ODROE_HOST'] ??\n"
        "      (platformPort == null ? '127.0.0.1' : '0.0.0.0')",
      ),
    );
    expect(
      bootstrap,
      contains(
        "Platform.environment['ODROE_PORT'] ??\n"
        "        platformPort ??",
      ),
    );
    expect(
      bootstrap,
      contains("developmentOriginFile == null || developmentOriginFile == ''"),
    );
    expect(bootstrap, contains('final appServer = await app.createServer();'));
    expect(bootstrap, contains('appServer.handler'));
    expect(bootstrap, contains('onError: appServer.onError'));
    expect(
      bootstrap,
      contains('IoServer.close(nativeServer!, force: true).ignore();'),
    );
    expect(bootstrap, contains('await IoServer.close(nativeServer);'));
    expect(bootstrap, contains('await appServer.close();'));
    expect('app.createServer()'.allMatches(bootstrap), hasLength(1));

    final id = Uri.encodeComponent('posts.read');
    final rpc = await client.getUrl(
      Uri.parse(
        'http://127.0.0.1:$port/__odroe/functions/$id'
        '?payload=%7B%22data%22%3A42%7D',
      ),
    );
    rpc.headers.set('origin', 'http://127.0.0.1:$port');
    rpc.headers.set('x-odroe-server-function', 'true');
    final rpcResponse = await rpc.close();
    final rpcBody = await rpcResponse.transform(utf8.decoder).join();
    expect(rpcResponse.statusCode, 200, reason: rpcBody);
    expect(jsonDecode(rpcBody), <String, Object?>{
      'version': 1,
      'type': 'data',
      'data': <String, Object?>{'id': 42, 'title': 'Odroe post 42'},
    });

    devMigration.writeAsStringSync('''
CREATE TABLE dev_watch_probe (id INTEGER PRIMARY KEY) STRICT;
''');
    var migrationApplied = false;
    var serverRecovered = false;
    Object? migrationError;
    Object? recoveryError;
    for (
      var attempt = 0;
      attempt < 100 && (!migrationApplied || !serverRecovered);
      attempt++
    ) {
      SqliteDatabase? inspection;
      try {
        inspection = SqliteDatabase.open(databaseFile.path);
        final count = await inspection.query(
          BoundSql.raw(
            'SELECT count(*) FROM main._odroe_migrations '
            'WHERE version = 9999',
          ),
          (row) => row.read(0, sqlInt),
        );
        migrationApplied = count.single == 1;
      } on Object catch (error) {
        migrationError = error;
      } finally {
        await inspection?.close();
      }
      if (migrationApplied) {
        try {
          final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:$port/posts/42?preview=true'),
          );
          request.headers.set(HttpHeaders.acceptHeader, 'application/json');
          final response = await request.close();
          final body = await response.transform(utf8.decoder).join();
          serverRecovered =
              response.statusCode == HttpStatus.ok &&
              body.contains('"location":"/posts/42?preview=true"');
        } on Object catch (error) {
          recoveryError = error;
        }
      }
      if (!migrationApplied || !serverRecovered) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    expect(migrationApplied, isTrue, reason: '$migrationError\n$output');
    expect(serverRecovered, isTrue, reason: '$recoveryError\n$output');

    final missing = await client.getUrl(
      Uri.parse(
        'http://127.0.0.1:$port/__odroe/functions/$id'
        '?payload=%7B%22data%22%3A404%7D',
      ),
    );
    missing.headers.set('origin', 'http://127.0.0.1:$port');
    missing.headers.set('x-odroe-server-function', 'true');
    final missingResponse = await missing.close();
    final missingBody = await missingResponse.transform(utf8.decoder).join();
    expect(
      missingResponse.statusCode,
      HttpStatus.notFound,
      reason: missingBody,
    );
    expect(jsonDecode(missingBody), <String, Object?>{
      'version': 1,
      'type': 'notFound',
      'message': 'Post not found.',
      'errorType': 'NotFound',
    });
  });
}
