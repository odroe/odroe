import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/database_sqlite.dart';
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
        ], timeout: const Duration(minutes: 2)),
      );
      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
      expect(artifact.existsSync(), isTrue);

      final databasePath = p.join(deployment.path, '.odroe', 'app.sqlite3');
      final port = await _unusedPort();
      final firstServer = await _startNativeServer(
        artifact,
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
      final function = Uri.encodeComponent('posts.read-title');
      final title = await _get(
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
      expect(title.status, HttpStatus.ok, reason: '${title.body}\n$logs');
      expect(jsonDecode(title.body), <String, Object?>{
        'version': 1,
        'type': 'data',
        'data': 'SQLite post 42',
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
        artifact,
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
        'data': 'Persisted post 42',
      }, reason: secondServer.logs.toString());
    },
    timeout: const Timeout(Duration(minutes: 3)),
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
}) async {
  final environment = <String, String>{
    for (final entry in Platform.environment.entries)
      if (entry.key != 'ODROE_SQLITE_PATH') entry.key: entry.value,
    'ODROE_HOST': '127.0.0.1',
    'ODROE_PORT': '$port',
    'ODROE_SQLITE_PATH': ?databasePath,
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
