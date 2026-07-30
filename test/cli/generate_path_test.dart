import 'dart:io';

import 'package:odroe/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('generate paths cannot escape the project', () async {
    final parent = await Directory.systemTemp.createTemp(
      'odroe_generate_path_test_',
    );
    addTearDown(() => parent.delete(recursive: true));
    final project = _createProject(parent);
    final outside = Directory(p.join(parent.path, 'outside'))
      ..createSync(recursive: true);
    final sentinel = File(p.join(outside.path, 'sentinel.txt'))
      ..writeAsStringSync('outside');

    for (final option in <String>['--routes', '--output', '--server-output']) {
      for (final unsafe in <String>[
        '../outside/target.dart',
        p.join(outside.path, 'target.dart'),
      ]) {
        final errors = StringBuffer();
        final code = await runOdroe(
          <String>['generate', '--project', project.path, option, unsafe],
          output: StringBuffer(),
          errors: errors,
        );

        expect(code, 64, reason: '$option $unsafe');
        expect(errors.toString(), contains(option), reason: '$option $unsafe');
      }
    }

    expect(sentinel.readAsStringSync(), 'outside');
    expect(File(p.join(outside.path, 'target.dart')).existsSync(), isFalse);
  });

  test(
    'generate paths cannot traverse an existing symbolic link',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'odroe_generate_link_test_',
      );
      addTearDown(() => parent.delete(recursive: true));
      final project = _createProject(parent);
      final outside = Directory(p.join(parent.path, 'outside'))
        ..createSync(recursive: true);
      Link(p.join(project.path, 'escape')).createSync(outside.path);

      for (final option in <String>[
        '--routes',
        '--output',
        '--server-output',
      ]) {
        final errors = StringBuffer();
        final code = await runOdroe(
          <String>[
            'generate',
            '--project',
            project.path,
            option,
            'escape/target.dart',
          ],
          output: StringBuffer(),
          errors: errors,
        );

        expect(code, 64, reason: option);
        expect(errors.toString(), contains(option), reason: option);
        expect(
          errors.toString(),
          contains('cannot traverse a symbolic link'),
          reason: option,
        );
      }

      expect(File(p.join(outside.path, 'target.dart')).existsSync(), isFalse);
    },
    skip: Platform.isWindows
        ? 'Symbolic link permissions vary on Windows.'
        : false,
  );
}

Directory _createProject(Directory parent) {
  final project = Directory(p.join(parent.path, 'project'))
    ..createSync(recursive: true);
  File(
    p.join(project.path, 'pubspec.yaml'),
  ).writeAsStringSync('name: path_fixture\n');
  return project;
}
