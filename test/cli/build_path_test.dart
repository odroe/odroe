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

  test('Flutter and prerender outputs cannot be nested', () async {
    final temporaryProject = await Directory.systemTemp.createTemp(
      'odroe_build_nested_web_outputs_',
    );
    final project = Directory(temporaryProject.resolveSymbolicLinksSync());
    addTearDown(() => project.delete(recursive: true));
    File(
      p.join(project.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: nested_web_outputs_fixture\n');
    Directory(
      p.join(project.path, 'lib', 'routes'),
    ).createSync(recursive: true);
    final errors = StringBuffer();

    final code = await runOdroe(
      <String>[
        'build',
        '--project',
        project.path,
        '--no-server',
        '--prerender-output',
        'build/web/prerender',
        '--',
        'web',
        '--output',
        'build/web',
      ],
      output: StringBuffer(),
      errors: errors,
    );

    expect(code, 64);
    expect(
      errors.toString(),
      contains(
        'Flutter build output and --prerender-output must either match or '
        'not overlap.',
      ),
    );
  });

  test(
    'managed Flutter Web output stays inside the project build tree',
    () async {
      final temporaryProject = await Directory.systemTemp.createTemp(
        'odroe_build_flutter_output_',
      );
      final project = Directory(temporaryProject.resolveSymbolicLinksSync());
      final outside = await Directory.systemTemp.createTemp(
        'odroe_build_flutter_output_outside_',
      );
      addTearDown(() async {
        await project.delete(recursive: true);
        await outside.delete(recursive: true);
      });
      File(
        p.join(project.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: flutter_output_fixture\n');
      Directory(
        p.join(project.path, 'lib', 'routes'),
      ).createSync(recursive: true);
      final publicSentinel =
          File(p.join(project.path, 'public', 'sentinel.txt'))
            ..createSync(recursive: true)
            ..writeAsStringSync('public');
      final outsideSentinel = File(p.join(outside.path, 'sentinel.txt'))
        ..writeAsStringSync('outside');

      for (final unsafe in <String>['public', 'build', outside.path]) {
        final errors = StringBuffer();
        final code = await runOdroe(
          <String>[
            'build',
            '--project',
            project.path,
            '--no-server',
            '--no-prerender',
            '--',
            'web',
            '--output',
            unsafe,
          ],
          output: StringBuffer(),
          errors: errors,
        );

        expect(code, 64, reason: unsafe);
        expect(
          errors.toString(),
          contains('Flutter Web output must resolve inside build/.'),
          reason: unsafe,
        );
        expect(publicSentinel.readAsStringSync(), 'public');
        expect(outsideSentinel.readAsStringSync(), 'outside');
      }

      final blockedFlutter = File(p.join(project.path, 'build', 'blocked-web'))
        ..createSync(recursive: true)
        ..writeAsStringSync('keep');
      final flutterErrors = StringBuffer();
      final flutterCode = await runOdroe(
        <String>[
          'build',
          '--project',
          project.path,
          '--no-server',
          '--no-prerender',
          '--',
          'web',
          '--output',
          'build/blocked-web',
        ],
        output: StringBuffer(),
        errors: flutterErrors,
      );
      expect(flutterCode, 64);
      expect(
        flutterErrors.toString(),
        contains(
          'Flutter Web output must be a regular directory or not exist.',
        ),
      );
      expect(blockedFlutter.readAsStringSync(), 'keep');

      final blockedPrerender =
          File(p.join(project.path, 'build', 'blocked-prerender'))
            ..createSync(recursive: true)
            ..writeAsStringSync('keep');
      final prerenderErrors = StringBuffer();
      final prerenderCode = await runOdroe(
        <String>[
          'build',
          '--project',
          project.path,
          '--no-server',
          '--prerender-output',
          'build/blocked-prerender',
        ],
        output: StringBuffer(),
        errors: prerenderErrors,
      );
      expect(prerenderCode, 64);
      expect(
        prerenderErrors.toString(),
        contains(
          '--prerender-output must be a regular directory or not exist.',
        ),
      );
      expect(blockedPrerender.readAsStringSync(), 'keep');
    },
  );

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
