import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/dart_command_lock.dart';
import '../support/process.dart';

void main() {
  test('dev exposes an explicit server target', () async {
    final output = StringBuffer();

    expect(
      await runOdroe(
        const <String>['dev', '--help'],
        output: output,
        errors: StringBuffer(),
      ),
      0,
    );
    expect(output.toString(), contains('--server-target'));
    expect(output.toString(), contains('native (default), cloudflare'));
  });

  test('Cloudflare development is an explicit server-only mode', () async {
    final errors = StringBuffer();

    final code = await runOdroe(
      const <String>[
        'dev',
        '--project',
        'example/app',
        '--server-target',
        'cloudflare',
      ],
      output: StringBuffer(),
      errors: errors,
    );

    expect(code, 64);
    expect(
      errors.toString(),
      'Cloudflare development currently requires --server-only. '
      'Run Flutter separately when needed.\n',
    );
  });

  test('Cloudflare server-only mode rejects Flutter arguments', () async {
    final errors = StringBuffer();

    final code = await runOdroe(
      const <String>[
        'dev',
        '--project',
        'example/app',
        '--server-target',
        'cloudflare',
        '--server-only',
        '--',
        '-d',
        'chrome',
      ],
      output: StringBuffer(),
      errors: errors,
    );

    expect(code, 64);
    expect(
      errors.toString(),
      'Cloudflare server-only development does not accept Flutter '
      'arguments.\n',
    );
  });

  test('Cloudflare development requires a project-local Wrangler', () async {
    final project = await _project();
    addTearDown(() => project.delete(recursive: true));
    final errors = StringBuffer();

    final code = await runOdroe(
      <String>[
        'dev',
        '--project',
        project.path,
        '--server-target',
        'cloudflare',
        '--server-only',
      ],
      output: StringBuffer(),
      errors: errors,
    );

    expect(code, 1);
    expect(
      errors.toString(),
      contains('Project-local Wrangler does not exist'),
    );
    expect(errors.toString(), contains('Run npm ci in the application first.'));
  });

  test('Cloudflare development requires application-owned config', () async {
    final project = await _project();
    addTearDown(() => project.delete(recursive: true));
    final wrangler = File(
      p.join(project.path, 'node_modules', 'wrangler', 'bin', 'wrangler.js'),
    );
    wrangler.createSync(recursive: true);
    final errors = StringBuffer();

    final code = await runOdroe(
      <String>[
        'dev',
        '--project',
        project.path,
        '--server-target',
        'cloudflare',
        '--server-only',
      ],
      output: StringBuffer(),
      errors: errors,
    );

    expect(code, 1);
    expect(errors.toString(), contains('wrangler.jsonc does not exist'));
    expect(errors.toString(), contains('application-owned'));
  });

  test(
    'Cloudflare development rebuilds and preserves last-known-good output',
    () async {
      final project = await _flutterProject();
      addTearDown(() => project.delete(recursive: true));
      final pubGet = await Process.run('flutter', const <String>[
        'pub',
        'get',
        '--offline',
      ], workingDirectory: project.path);
      expect(pubGet.exitCode, 0, reason: '${pubGet.stdout}\n${pubGet.stderr}');
      final errors = StringBuffer();
      expect(
        await runOdroe(
          <String>['init', '--full-stack', '--project', project.path],
          output: StringBuffer(),
          errors: errors,
        ),
        0,
        reason: errors.toString(),
      );

      Directory(
        p.join(project.path, 'build', 'web'),
      ).createSync(recursive: true);
      final fakeWrangler = File(
        p.join(project.path, 'node_modules', 'wrangler', 'bin', 'wrangler.js'),
      )..createSync(recursive: true);
      final wranglerMarker = File(p.join(project.path, 'wrangler-started'));
      fakeWrangler.writeAsStringSync(r'''
require('node:fs').writeFileSync('wrangler-started', 'started');
console.log(`FAKE_WRANGLER ${JSON.stringify(process.argv.slice(2))}`);
process.on('SIGTERM', () => {
  console.log('FAKE_WRANGLER_STOP');
  process.exit(0);
});
setInterval(() => {}, 1000);
''');

      final duplicateFirst = File(
        p.join(project.path, 'lib', 'routes', '[first]', 'page.dart'),
      )..createSync(recursive: true);
      final duplicateSecond = File(
        p.join(project.path, 'lib', 'routes', '[second]', 'page.dart'),
      )..createSync(recursive: true);
      duplicateFirst.writeAsStringSync('// Duplicate route fixture.\n');
      duplicateSecond.writeAsStringSync('// Duplicate route fixture.\n');
      final generationErrors = StringBuffer();
      expect(
        await runOdroe(
          <String>[
            'dev',
            '--project',
            project.path,
            '--server-target',
            'cloudflare',
            '--server-only',
          ],
          output: StringBuffer(),
          errors: generationErrors,
        ),
        1,
      );
      expect(generationErrors.toString(), isNotEmpty);
      expect(wranglerMarker.existsSync(), isFalse);
      duplicateFirst.parent.deleteSync(recursive: true);
      duplicateSecond.parent.deleteSync(recursive: true);

      final cloudflareServer = File(
        p.join(project.path, 'lib', 'server_cloudflare.dart'),
      );
      final validCloudflareServer = cloudflareServer.readAsStringSync();
      cloudflareServer.writeAsStringSync(
        '$validCloudflareServer\ninvalid Dart\n',
      );
      final initialCompile = await Process.run(dartExecutable, const <String>[
        'run',
        'odroe',
        'dev',
        '--server-target',
        'cloudflare',
        '--server-only',
      ], workingDirectory: project.path);
      expect(
        initialCompile.exitCode,
        isNot(0),
        reason: '${initialCompile.stdout}\n${initialCompile.stderr}',
      );
      expect(wranglerMarker.existsSync(), isFalse);
      expect(
        File(
          p.join(project.path, 'build', 'odroe', 'cloudflare', 'server.js'),
        ).existsSync(),
        isFalse,
      );
      cloudflareServer.writeAsStringSync(validCloudflareServer);
      final nonRoutePage =
          File(p.join(project.path, 'lib', 'shared', 'page.dart'))
            ..createSync(recursive: true)
            ..writeAsStringSync("const sharedPageValue = 'one';\n");

      final process = await Process.start(dartExecutable, const <String>[
        'run',
        'odroe',
        'dev',
        '--server-target',
        'cloudflare',
        '--server-only',
        '--port',
        '0',
      ], workingDirectory: project.path);
      final logs = StringBuffer();
      final stdout = process.stdout.transform(utf8.decoder).listen(logs.write);
      final stderr = process.stderr.transform(utf8.decoder).listen(logs.write);
      int? processExitCode;
      final exitCode = process.exitCode.then((code) {
        processExitCode = code;
        return code;
      });
      addTearDown(() async {
        if (processExitCode == null) {
          await terminateTestProcess(process, exitCode);
        }
        await stdout.cancel();
        await stderr.cancel();
      });

      await _waitFor(
        () => logs.toString().contains('FAKE_WRANGLER'),
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(wranglerMarker.readAsStringSync(), 'started');
      expect(
        logs.toString(),
        allOf(
          contains('build/odroe/cloudflare/worker.mjs'),
          contains('"--local"'),
          contains('"--ip","127.0.0.1"'),
          contains('"--port","0"'),
        ),
      );
      Future<void> waitForNextSuccessfulBuild() async {
        final previous = _occurrences(
          logs.toString(),
          'Built Cloudflare Worker',
        );
        await _waitFor(
          () =>
              _occurrences(logs.toString(), 'Built Cloudflare Worker') >
              previous,
          processExitCode: () => processExitCode,
          logs: logs,
        );
      }

      nonRoutePage.writeAsStringSync("const sharedPageValue = 'two';\n");
      await waitForNextSuccessfulBuild();
      final artifact = File(
        p.join(project.path, 'build', 'odroe', 'cloudflare', 'server.js'),
      );
      final initialArtifact = base64Encode(artifact.readAsBytesSync());
      final route = File(p.join(project.path, 'lib', 'routes', 'route.dart'));
      final original = route.readAsStringSync();
      expect(original, contains('Full-stack Odroe'));

      route.writeAsStringSync(
        original.replaceAll('Full-stack Odroe', 'Cloudflare reload one'),
      );
      await waitForNextSuccessfulBuild();
      final reloadedArtifact = base64Encode(artifact.readAsBytesSync());
      expect(reloadedArtifact, isNot(initialArtifact));

      final invalidLogStart = logs.length;
      route.writeAsStringSync('${route.readAsStringSync()}\ninvalid Dart\n');
      await _waitFor(
        () => logs.toString().substring(invalidLogStart).contains('error:'),
        processExitCode: () => processExitCode,
        logs: logs,
      );
      expect(base64Encode(artifact.readAsBytesSync()), reloadedArtifact);

      route.writeAsStringSync(
        original.replaceAll('Full-stack Odroe', 'Cloudflare reload two'),
      );
      await waitForNextSuccessfulBuild();
      expect(base64Encode(artifact.readAsBytesSync()), isNot(reloadedArtifact));

      process.kill(ProcessSignal.sigterm);
      expect(
        await exitCode.timeout(const Duration(seconds: 15)),
        0,
        reason: logs.toString(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(logs.toString(), contains('FAKE_WRANGLER_STOP'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: Platform.isWindows
        ? 'Process signal integration differs on Windows.'
        : !_nodeAvailable
        ? 'Node is required for the Cloudflare development runtime.'
        : false,
  );
}

Future<Directory> _project() async {
  final project = await Directory.systemTemp.createTemp(
    'odroe-cloudflare-dev-',
  );
  File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: cloudflare_dev_fixture
environment:
  sdk: ^3.10.0
''');
  return project;
}

Future<Directory> _flutterProject() async {
  final project = await Directory.systemTemp.createTemp(
    'odroe-cloudflare-dev-integration-',
  );
  File(p.join(project.path, '.metadata')).writeAsStringSync('''
project_type: app
''');
  File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: cloudflare_dev_integration
environment:
  sdk: ^3.10.0
dependencies:
  flutter:
    sdk: flutter
  odroe:
    path: ${Directory.current.absolute.path}
''');
  File(p.join(project.path, 'lib', 'main.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_flutterEmptyMain);
  return project;
}

Future<void> _waitFor(
  bool Function() condition, {
  required int? Function() processExitCode,
  required StringBuffer logs,
}) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    if (condition()) return;
    final code = processExitCode();
    if (code != null) {
      fail('Cloudflare development exited with $code.\n$logs');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for Cloudflare development.\n$logs');
}

int _occurrences(String source, String pattern) =>
    pattern.allMatches(source).length;

final bool _nodeAvailable = () {
  try {
    return Process.runSync('node', const <String>['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}();

const _flutterEmptyMain = '''
import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Hello World!'),
        ),
      ),
    );
  }
}
''';
