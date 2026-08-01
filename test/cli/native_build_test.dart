import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final process = await Process.start(
        artifact.path,
        const <String>[],
        workingDirectory: deployment.path,
        environment: <String, String>{
          ...Platform.environment,
          'ODROE_HOST': '127.0.0.1',
          'ODROE_PORT': '$port',
        },
      );
      final logs = StringBuffer();
      final stdout = process.stdout.transform(utf8.decoder).listen(logs.write);
      final stderr = process.stderr.transform(utf8.decoder).listen(logs.write);
      addTearDown(() async {
        process.kill(ProcessSignal.sigterm);
        try {
          await process.exitCode.timeout(const Duration(seconds: 10));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
        }
        await stdout.cancel();
        await stderr.cancel();
      });

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
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
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
