import 'dart:io';

import 'package:odroe/src/cli/build.dart';
import 'package:odroe/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('prerender CLI defaults are bounded and crawling is explicit', () async {
    final output = StringBuffer();
    final code = await runOdroe(
      const <String>['build', '--help'],
      output: output,
      errors: StringBuffer(),
    );
    final usage = output.toString();

    expect(code, 0);
    expect(usage, contains('--[no-]server'));
    expect(usage, contains('Emit a deployable Odroe server artifact.'));
    expect(usage, contains('--sqlite-migrations'));
    expect(usage, contains('Override odroe.yaml SQLite migrations'));
    expect(usage, contains('--prerender-crawl'));
    expect(usage, contains('Discover additional same-origin HTML links.'));
    expect(usage, contains('--prerender-concurrency'));
    expect(usage, contains('(defaults to "4")'));
    expect(usage, contains('--prerender-max-routes'));
    expect(usage, contains('(defaults to "1000")'));
    expect(usage, contains('--prerender-max-response-bytes'));
    expect(usage, contains('(defaults to "1048576")'));
  });

  test('prerender readiness accepts only the generated loopback line', () {
    expect(parsePrerenderReadyLine('https://example.com'), isNull);
    expect(
      parsePrerenderReadyLine(
        'application log before ready: http://127.0.0.1:9999',
      ),
      isNull,
    );
    expect(
      parsePrerenderReadyLine('Odroe listening on http://localhost:3000'),
      isNull,
    );
    expect(
      parsePrerenderReadyLine('Odroe listening on http://127.0.0.1:0'),
      isNull,
    );
    expect(
      parsePrerenderReadyLine('Odroe listening on http://127.0.0.1:65536'),
      isNull,
    );
    expect(
      parsePrerenderReadyLine('Odroe listening on http://127.0.0.1:4321'),
      Uri.parse('http://127.0.0.1:4321'),
    );
  });

  test('SQLite migrations require a Native bundle or prerender', () async {
    final project = await Directory.systemTemp.createTemp(
      'odroe_build_migration_consumer_',
    );
    addTearDown(() => project.delete(recursive: true));
    File(
      p.join(project.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: migration_consumer_fixture\n');
    Directory(
      p.join(project.path, 'lib', 'routes'),
    ).createSync(recursive: true);

    for (final arguments in <List<String>>[
      <String>[
        '--server-only',
        '--server-target',
        ServerBuildTarget.cloudflare.name,
      ],
      const <String>['--no-server', '--no-prerender'],
    ]) {
      final errors = StringBuffer();
      final code = await runOdroe(
        <String>[
          'build',
          '--project',
          project.path,
          ...arguments,
          '--sqlite-migrations',
          'missing',
        ],
        output: StringBuffer(),
        errors: errors,
      );

      expect(code, 64, reason: arguments.join(' '));
      expect(
        errors.toString(),
        contains(
          '--sqlite-migrations requires a Native server build or prerender.',
        ),
        reason: arguments.join(' '),
      );
      expect(errors.toString(), isNot(contains('does not exist')));
    }
  });

  test('build identifies a missing configured SQLite history', () async {
    final project = await Directory.systemTemp.createTemp(
      'odroe_build_configured_migrations_',
    );
    addTearDown(() => project.delete(recursive: true));
    File(
      p.join(project.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: configured_migrations_fixture\n');
    File(
      p.join(project.path, 'odroe.yaml'),
    ).writeAsStringSync('sqlite_migrations: missing\n');
    Directory(
      p.join(project.path, 'lib', 'routes'),
    ).createSync(recursive: true);
    final errors = StringBuffer();

    final code = await runOdroe(
      <String>['build', '--project', project.path, '--server-only'],
      output: StringBuffer(),
      errors: errors,
    );

    expect(code, 1);
    expect(
      errors.toString(),
      contains('odroe.yaml sqlite_migrations must be a regular directory.'),
    );
  });

  test('build outputs cannot escape or replace project content', () async {
    final parent = await Directory.systemTemp.createTemp(
      'odroe_build_path_test_',
    );
    addTearDown(() => parent.delete(recursive: true));
    final project = Directory(p.join(parent.path, 'project'))
      ..createSync(recursive: true);
    final build = Directory(p.join(project.path, 'build'))
      ..createSync(recursive: true);
    final publicSentinel = File(p.join(project.path, 'public', 'sentinel.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('public');
    final outsideSentinel = File(p.join(parent.path, 'sentinel.txt'))
      ..writeAsStringSync('outside');

    for (final unsafe in <String>[
      '.',
      '..',
      'public',
      'build/../public',
      outsideSentinel.absolute.path,
    ]) {
      expect(
        () => resolveBuildOutputPath(
          project,
          unsafe,
          option: '--prerender-output',
        ),
        throwsFormatException,
        reason: unsafe,
      );
    }

    expect(
      resolveBuildOutputPath(
        project,
        'build/odroe/server',
        option: '--server-artifact',
      ),
      p.join(build.path, 'odroe', 'server'),
    );
    expect(publicSentinel.readAsStringSync(), 'public');
    expect(outsideSentinel.readAsStringSync(), 'outside');
  });

  test(
    'build outputs cannot traverse an existing symbolic link',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'odroe_build_link_test_',
      );
      addTearDown(() => parent.delete(recursive: true));
      final project = Directory(p.join(parent.path, 'project'))
        ..createSync(recursive: true);
      final build = Directory(p.join(project.path, 'build'))..createSync();
      final outside = Directory(p.join(parent.path, 'outside'))..createSync();
      Link(p.join(build.path, 'escape')).createSync(outside.path);

      expect(
        () => resolveBuildOutputPath(
          project,
          'build/escape/server',
          option: '--server-artifact',
        ),
        throwsFormatException,
      );
    },
    skip: Platform.isWindows
        ? 'Symbolic link permissions vary on Windows.'
        : false,
  );
}
