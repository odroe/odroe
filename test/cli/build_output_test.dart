import 'dart:io';

import 'package:odroe/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late Directory project;

  setUp(() async {
    temporary = Directory.systemTemp.createTempSync('odroe-build-test-');
    project = Directory(p.join(temporary.path, 'app'))..createSync();
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: build_fixture
environment:
  sdk: ^3.10.0
''');
    final pubspec = File(p.join(project.path, 'pubspec.yaml'));
    pubspec.writeAsStringSync(
      '${pubspec.readAsStringSync()}\ndependencies:\n  odroe:\n    path: ${Directory.current.path}\n',
    );
    final resolved = await Process.run('flutter', <String>[
      'pub',
      'get',
      '--offline',
    ], workingDirectory: project.path);
    expect(
      resolved.exitCode,
      0,
      reason: '${resolved.stdout}\n${resolved.stderr}',
    );
    final route = File(p.join(project.path, 'lib/routes/route.dart'));
    route.parent.createSync(recursive: true);
    route.writeAsStringSync('''
import 'package:odroe/document.dart';
import 'package:odroe/router.dart';
final route = AppRoute<NoParams, NoSearch, NoData>().document(
  (_) => const RouteDocument(body: HtmlText('safe build')),
);
''');
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  Future<int> build(String output, [StringBuffer? errors]) => runOdroe(
    <String>['build', '--project', project.path, '--prerender-output', output],
    output: StringBuffer(),
    errors: errors ?? StringBuffer(),
  );

  for (final target in <String>[
    'public',
    'lib',
    '.',
    '..',
    'build',
    'build/odroe',
  ]) {
    test('rejects $target before touching existing files', () async {
      final directory = Directory(p.join(project.path, target))
        ..createSync(recursive: true);
      final sentinel = File(p.join(directory.path, 'keep.txt'))
        ..writeAsStringSync('keep');
      final errors = StringBuffer();
      expect(await build(target, errors), isNot(0), reason: '$errors');
      expect(sentinel.readAsStringSync(), 'keep');
      expect(
        File(p.join(project.path, 'build/odroe/server')).existsSync(),
        isFalse,
      );
    });
  }

  test('rejects an unowned existing output', () async {
    final output = Directory(p.join(project.path, 'build/site'))
      ..createSync(recursive: true);
    final sentinel = File(p.join(output.path, 'keep.txt'))
      ..writeAsStringSync('keep');
    expect(await build('build/site'), isNot(0));
    expect(sentinel.readAsStringSync(), 'keep');
  });

  for (final option in <String>['--output', '--server-output']) {
    test('rejects $option overlap before generating files', () async {
      final sentinel = File(p.join(project.path, 'build/site/routes.dart'));
      sentinel.parent.createSync(recursive: true);
      sentinel.writeAsStringSync('keep');
      final code = await runOdroe(
        <String>[
          'build',
          '--project',
          project.path,
          '--prerender-output',
          'build/site',
          option,
          'build/site/routes.dart',
        ],
        output: StringBuffer(),
        errors: StringBuffer(),
      );
      expect(code, isNot(0));
      expect(sentinel.readAsStringSync(), 'keep');
      expect(
        File(p.join(project.path, 'lib/routes.dart')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(project.path, '.dart_tool/odroe/server.dart')).existsSync(),
        isFalse,
      );
    });
  }

  test('rejects symlinked output ancestors', () async {
    final outside = Directory(p.join(temporary.path, 'outside'))..createSync();
    File(p.join(outside.path, 'keep.txt')).writeAsStringSync('keep');
    Directory(p.join(project.path, 'build')).createSync();
    Link(p.join(project.path, 'build/linked')).createSync(outside.path);
    expect(await build('build/linked/site'), isNot(0));
    expect(outside.listSync().length, 1);
  });

  test('rejects public symlinks before copying assets', () async {
    Link(p.join(project.path, 'public')).createSync(project.path);
    expect(await build('build/site'), isNot(0));
    expect(Directory(p.join(project.path, 'build')).existsSync(), isFalse);
  });

  test(
    'rejects absolute paths, traversal, files, and foreign ownership',
    () async {
      expect(await build(p.join(temporary.path, 'site')), isNot(0));
      expect(await build('build/../site'), isNot(0));
      Directory(p.join(project.path, 'build')).createSync();
      File(p.join(project.path, 'build/site')).writeAsStringSync('keep');
      expect(await build('build/site'), isNot(0));
      File(p.join(project.path, 'build/site')).deleteSync();
      Directory(p.join(project.path, 'build/site')).createSync();
      final marker = File(p.join(project.path, 'build/site/.odroe-prerender'))
        ..writeAsStringSync('odroe-prerender-v1:another_project\n');
      expect(await build('build/site'), isNot(0));
      expect(marker.readAsStringSync(), 'odroe-prerender-v1:another_project\n');
    },
  );

  test(
    'publishes and rebuilds owned output; render failure preserves it',
    () async {
      final errors = StringBuffer();
      expect(await build('build/site', errors), 0, reason: '$errors');
      final index = File(p.join(project.path, 'build/site/index.html'));
      final original = index.readAsStringSync();
      expect(original, contains('safe build'));
      final stale = File(p.join(project.path, 'build/site/stale.html'))
        ..writeAsStringSync('stale');
      expect(await build('build/site', errors), 0, reason: '$errors');
      expect(stale.existsSync(), isFalse);
      final route = File(p.join(project.path, 'lib/routes/route.dart'));
      route.writeAsStringSync(
        route.readAsStringSync().replaceFirst(
          "(_) => const RouteDocument(body: HtmlText('safe build'))",
          "(_) => throw StateError('render failed')",
        ),
      );
      expect(await build('build/site', errors), isNot(0));
      expect(index.readAsStringSync(), original);
      expect(
        Directory(p.join(project.path, 'build')).listSync().where(
          (entry) => p.basename(entry.path).startsWith('.odroe-prerender-'),
        ),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
