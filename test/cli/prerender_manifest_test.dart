import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/src/cli/prerender_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('loads, normalizes, and merges application locations', () async {
    final locations = await loadPrerenderLocations(
      projectRoot: Directory('example/app').absolute,
      packageName: 'odroe_example',
      staticLocations: const <String>['/', '/about///', '/pricing', '/about'],
      dartExecutable: 'dart',
    );

    expect(locations, <String>[
      '/',
      '/about',
      '/docs/getting-started',
      '/docs/routing',
      '/posts/42',
      '/pricing',
    ]);
  });

  test('rejects locations that cannot be statically rendered', () {
    for (final location in <String>[
      'relative',
      'https://example.com/docs',
      '/docs?draft=true',
      '/docs#intro',
    ]) {
      expect(
        () => normalizePrerenderLocations(<Uri>[Uri.parse(location)]),
        throwsFormatException,
        reason: location,
      );
    }
  });

  test(
    'times out and reaps a hanging application callback',
    () async {
      final projectRoot = await _createHangingProject();
      addTearDown(() async {
        if (projectRoot.existsSync()) {
          await projectRoot.delete(recursive: true);
        }
      });

      await expectLater(
        () => loadPrerenderLocations(
          projectRoot: projectRoot,
          packageName: 'prerender_timeout_fixture',
          staticLocations: const <String>['/'],
          dartExecutable: 'dart',
          callbackTimeout: const Duration(milliseconds: 250),
          terminationGracePeriod: const Duration(milliseconds: 100),
        ),
        throwsA(
          isA<TimeoutException>()
              .having(
                (error) => error.toString(),
                'message',
                contains(
                  'Application prerender locations timed out after '
                  '250 milliseconds.',
                ),
              )
              .having(
                (error) => error.toString(),
                'stdout',
                isNot(contains('fixture stdout secret')),
              )
              .having(
                (error) => error.toString(),
                'stderr',
                isNot(contains('fixture stderr secret')),
              ),
        ),
      );

      final temporaryDirectory = Directory(
        p.join(projectRoot.path, '.dart_tool', 'odroe'),
      );
      expect(temporaryDirectory.listSync(), isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test(
    'callback timeout closes inherited stdout and stderr subscriptions',
    () async {
      final projectRoot = await _createInheritedStdioProject();
      final childPidFile = File(p.join(projectRoot.path, 'child.pid'));
      final harness = await _createDrainHarness();
      addTearDown(() async {
        await _killFixtureChild(childPidFile);
        if (harness.existsSync()) await harness.delete();
        if (projectRoot.existsSync()) {
          await projectRoot.delete(recursive: true);
        }
      });

      final process = await Process.start('dart', <String>[
        'run',
        harness.path,
        projectRoot.path,
      ], workingDirectory: Directory.current.path);
      final output = StringBuffer();
      final stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .listen(output.write);
      final stderrDone = process.stderr.drain<void>();
      var exited = false;
      try {
        final code = await process.exitCode.timeout(const Duration(seconds: 7));
        exited = true;
        expect(code, 0);
        expect(output.toString(), contains('bounded drain complete'));
      } finally {
        if (!exited) {
          process.kill(ProcessSignal.sigkill);
          try {
            await process.exitCode.timeout(const Duration(seconds: 1));
          } on TimeoutException {
            // Keep the regression itself bounded on a broken runtime.
          }
        }
        await stdoutSubscription.cancel();
        await stderrDone.timeout(const Duration(seconds: 1));
        await _killFixtureChild(childPidFile);
      }

      expect(
        childPidFile.existsSync(),
        isTrue,
        reason: 'The callback must exit after spawning the inherited pipe.',
      );
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}

Future<Directory> _createHangingProject() async {
  final root = await Directory.systemTemp.createTemp(
    'odroe_prerender_timeout.',
  );
  final library = Directory(p.join(root.path, 'lib'));
  final dartTool = Directory(p.join(root.path, '.dart_tool'));
  await library.create(recursive: true);
  await dartTool.create(recursive: true);

  await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: prerender_timeout_fixture
environment:
  sdk: ^3.10.0
''');
  await File(p.join(library.path, 'prerender.dart')).writeAsString(r'''
import 'dart:async';
import 'dart:io';

Future<Iterable<Uri>> prerenderLocations() async {
  stdout.writeln('fixture stdout secret');
  stderr.writeln('fixture stderr secret');
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) {});
  }
  Timer.periodic(const Duration(seconds: 1), (_) {});
  await Completer<void>().future;
  return const <Uri>[];
}
''');
  await File(p.join(dartTool.path, 'package_config.json')).writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'prerender_timeout_fixture',
          'rootUri': '../',
          'packageUri': 'lib/',
          'languageVersion': '3.10',
        },
      ],
    }),
  );
  return root;
}

Future<Directory> _createInheritedStdioProject() async {
  final root = await Directory.systemTemp.createTemp(
    'odroe_prerender_inherited_stdio.',
  );
  final library = Directory(p.join(root.path, 'lib'));
  final tool = Directory(p.join(root.path, 'tool'));
  final dartTool = Directory(p.join(root.path, '.dart_tool'));
  await library.create(recursive: true);
  await tool.create(recursive: true);
  await dartTool.create(recursive: true);

  await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: prerender_inherited_stdio_fixture
environment:
  sdk: ^3.10.0
''');
  await File(p.join(library.path, 'prerender.dart')).writeAsString(r'''
import 'dart:io';

Future<Iterable<Uri>> prerenderLocations() async {
  final child = await Process.start(
    Platform.resolvedExecutable,
    <String>['run', 'tool/inherited_stdio.dart'],
    mode: ProcessStartMode.inheritStdio,
  );
  await File('child.pid').writeAsString('${child.pid}', flush: true);
  return const <Uri>[];
}
''');
  await File(p.join(tool.path, 'inherited_stdio.dart')).writeAsString(r'''
import 'dart:async';
import 'dart:io';

void main() {
  stdout.writeln('inherited stdout');
  stderr.writeln('inherited stderr');
  Timer(const Duration(seconds: 30), () {});
}
''');
  await File(p.join(dartTool.path, 'package_config.json')).writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'prerender_inherited_stdio_fixture',
          'rootUri': '../',
          'packageUri': 'lib/',
          'languageVersion': '3.10',
        },
      ],
    }),
  );
  return root;
}

Future<File> _createDrainHarness() async {
  final directory = Directory(
    p.join(Directory.current.path, '.dart_tool', 'odroe'),
  );
  await directory.create(recursive: true);
  final file = File(
    p.join(
      directory.path,
      'prerender-drain-test-${pid}_${DateTime.now().microsecondsSinceEpoch}.dart',
    ),
  );
  await file.writeAsString(r'''
import 'dart:async';
import 'dart:io';

import 'package:odroe/src/cli/prerender_manifest.dart';

Future<void> main(List<String> arguments) async {
  try {
    await loadPrerenderLocations(
      projectRoot: Directory(arguments.single),
      packageName: 'prerender_inherited_stdio_fixture',
      staticLocations: const <String>['/'],
      dartExecutable: 'dart',
      callbackTimeout: const Duration(seconds: 2),
      terminationGracePeriod: const Duration(milliseconds: 100),
    );
  } on TimeoutException {
    stdout.writeln('bounded drain complete');
    return;
  }
  throw StateError('Inherited output unexpectedly drained.');
}
''');
  return file;
}

Future<void> _killFixtureChild(File pidFile) async {
  if (!pidFile.existsSync()) return;
  final childPid = int.tryParse(await pidFile.readAsString());
  if (childPid != null) Process.killPid(childPid);
  await Future<void>.delayed(const Duration(milliseconds: 200));
}
