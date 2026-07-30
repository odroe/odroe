import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _skipReason =
    'Set ODROE_WRANGLER to a Wrangler v4 executable to run this test.';

void main() {
  final configuredWrangler = Platform.environment['ODROE_WRANGLER'];

  test(
    'D1 adapter passes a real local Workerd integration',
    () async {
      final wrangler = configuredWrangler!;
      final temporary = await Directory.systemTemp.createTemp(
        'odroe_database_d1_workerd_',
      );
      final processOutput = StringBuffer();
      final logFile = File('${temporary.path}/wrangler.log');
      Process? process;
      HttpClient? client;
      StreamSubscription<String>? stdoutSubscription;
      StreamSubscription<String>? stderrSubscription;

      addTearDown(() async {
        client?.close(force: true);
        if (process case final running?) await _terminate(running);
        await stdoutSubscription?.cancel();
        await stderrSubscription?.cancel();
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      });

      final compiled = File('${temporary.path}/workerd_fixture.js');
      final compilation = await Process.run(
        _dartExecutable,
        <String>[
          'compile',
          'js',
          '-O4',
          '--no-source-maps',
          'test/database_d1/workerd_fixture.dart',
          '-o',
          compiled.path,
        ],
        workingDirectory: Directory.current.path,
      ).timeout(const Duration(seconds: 45));
      expect(
        compilation.exitCode,
        0,
        reason: '${compilation.stdout}\n${compilation.stderr}',
      );

      final worker = File('${temporary.path}/worker.mjs');
      await worker.writeAsString(_workerSource);
      final config = File('${temporary.path}/wrangler.jsonc');
      await config.writeAsString(_wranglerConfig);
      final persistence = await Directory('${temporary.path}/state').create();
      final xdgConfig = await Directory('${temporary.path}/xdg').create();
      final port = await _unusedPort();
      final inspectorPort = await _unusedPort();

      process = await Process.start(
        wrangler,
        <String>[
          'dev',
          '--config',
          config.path,
          '--local',
          '--ip',
          InternetAddress.loopbackIPv4.address,
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
        workingDirectory: temporary.path,
        environment: <String, String>{
          'CI': 'true',
          'NO_COLOR': '1',
          'WRANGLER_LOG_PATH': logFile.path,
          'XDG_CONFIG_HOME': xdgConfig.path,
        },
        includeParentEnvironment: true,
      );
      stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .listen(processOutput.write);
      stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .listen(processOutput.write);

      int? exitCode;
      unawaited(
        process.exitCode.then<void>((value) {
          exitCode = value;
        }),
      );

      client = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 500);
      final origin = Uri.parse('http://127.0.0.1:$port');
      await _waitUntilReady(
        client,
        origin.resolve('/health'),
        exited: () => exitCode,
        diagnostics: () => processOutput.toString(),
      );

      final response = await _get(
        client,
        origin.resolve('/test'),
        timeout: const Duration(seconds: 45),
      );
      expect(
        response.statusCode,
        HttpStatus.ok,
        reason: '${response.body}\n${processOutput.toString()}',
      );
      expect(response.body, 'ok');
    },
    skip: configuredWrangler == null || configuredWrangler.isEmpty
        ? _skipReason
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _waitUntilReady(
  HttpClient client,
  Uri uri, {
  required int? Function() exited,
  required String Function() diagnostics,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final exitCode = exited();
    if (exitCode != null) {
      throw StateError(
        'Wrangler exited with code $exitCode before becoming ready.\n'
        '${diagnostics()}',
      );
    }
    try {
      final response = await _get(
        client,
        uri,
        timeout: const Duration(seconds: 2),
      );
      if (response.statusCode == HttpStatus.ok && response.body == 'ready') {
        return;
      }
      throw StateError(
        'Wrangler health check returned ${response.statusCode}: '
        '${response.body}\n${diagnostics()}',
      );
    } on SocketException {
      // Workerd has not bound its local port yet.
    } on HttpException {
      // The dev server may accept a socket before its Worker is ready.
    } on TimeoutException {
      // Wrangler may still be compiling the Worker.
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException(
    'Wrangler did not become ready.\n${diagnostics()}',
    const Duration(seconds: 30),
  );
}

Future<({int statusCode, String body})> _get(
  HttpClient client,
  Uri uri, {
  required Duration timeout,
}) async {
  final request = await client.getUrl(uri).timeout(timeout);
  final response = await request.close().timeout(timeout);
  final body = await response.transform(utf8.decoder).join().timeout(timeout);
  return (statusCode: response.statusCode, body: body);
}

Future<int> _unusedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _terminate(Process process) async {
  final exit = process.exitCode;
  process.kill();
  try {
    await exit.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await exit.timeout(const Duration(seconds: 5));
  }
}

String get _dartExecutable {
  if (Platform.resolvedExecutable.endsWith('/dart')) {
    return Platform.resolvedExecutable;
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    return '$flutterRoot/bin/cache/dart-sdk/bin/dart';
  }
  return 'dart';
}

const _workerSource = '''
import "./workerd_fixture.js";

export default {
  async fetch(request, env) {
    if (new URL(request.url).pathname !== "/test") {
      return new Response("ready");
    }
    try {
      await globalThis.odroeD1WorkerdTest(env);
      return new Response("ok");
    } catch (error) {
      const message =
        typeof error?.stack === "string" ? error.stack : String(error);
      return new Response(message, { status: 500 });
    }
  },
};
''';

const _wranglerConfig = '''
{
  "name": "odroe-d1-workerd-test",
  "main": "worker.mjs",
  "compatibility_date": "2026-07-29",
  "d1_databases": [
    {
      "binding": "DB",
      "database_name": "odroe-d1-workerd-test",
      "database_id": "11111111-1111-4111-8111-111111111111"
    }
  ]
}
''';
