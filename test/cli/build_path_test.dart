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
