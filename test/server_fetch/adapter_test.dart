import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../support/dart_command_lock.dart';

void main() {
  test('dart2js output passes the Node Fetch runtime smoke', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'odroe_server_fetch_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final output = File('${temporary.path}/fixture.js');

    final compile = await withDartCommandLock(
      () => Process.run('dart', <String>[
        'compile',
        'js',
        '-O4',
        '--no-source-maps',
        'test/server_fetch/fixture.dart',
        '-o',
        output.path,
      ]),
    ).timeout(const Duration(seconds: 30));
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');

    final javaScript = await output.readAsString();
    expect(javaScript, isNot(matches(RegExp(r'\beval\s*\('))));
    expect(javaScript, isNot(matches(RegExp(r'\bnew\s+Function\s*\('))));

    final sources = await Future.wait<String>(
      <String>[
        'lib/src/server_fetch/adapter.dart',
        'lib/src/server_fetch/http.dart',
      ].map((path) => File(path).readAsString()),
    );
    expect(sources.join(), isNot(contains('dart:js_interop_unsafe')));

    final smoke = await Process.run('node', <String>[
      'test/server_fetch/smoke.mjs',
      output.path,
    ]).timeout(const Duration(seconds: 30));
    expect(smoke.exitCode, 0, reason: '${smoke.stdout}\n${smoke.stderr}');
    expect(smoke.stdout, contains('server_fetch smoke passed'));
  });
}
