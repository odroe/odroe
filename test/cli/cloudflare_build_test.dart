import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

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

      final smoke = await Process.run('node', <String>[
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
      ]).timeout(const Duration(seconds: 30));
      expect(smoke.exitCode, 0, reason: '${smoke.stdout}\n${smoke.stderr}');
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

Future<void> _buildWorker(Directory project, String artifact) async {
  final build = await Process.run('dart', <String>[
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
  ]).timeout(const Duration(minutes: 2));
  expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
}

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
  process.kill(ProcessSignal.sigterm);
  try {
    await exitCode.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await exitCode.timeout(const Duration(seconds: 5));
  }
}

extension on String {
  String quote() => "'${replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
}
