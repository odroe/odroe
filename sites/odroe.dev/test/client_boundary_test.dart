import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('client route closure compiles and runs as JavaScript', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'odroe_site_client_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final output = File('${temporary.path}/client.js');

    final compile = await Process.run(Platform.resolvedExecutable, <String>[
      'compile',
      'js',
      '-O4',
      '--no-source-maps',
      'test/fixtures/client.dart',
      '-o',
      output.path,
    ]).timeout(const Duration(seconds: 30));
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');

    final run = await Process.run('node', <String>[
      output.path,
    ]).timeout(const Duration(seconds: 10));
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect(run.stdout.toString().trim(), '1');
  });
}
