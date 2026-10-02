import 'dart:convert';
import 'dart:io';

import 'package:odroe/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory parent;
  late String target;

  setUp(() async {
    parent = await Directory.systemTemp.createTemp('odroe_create_hosted_');
    target = p.join(parent.path, 'app');
  });
  tearDown(() => parent.delete(recursive: true));

  test(
    'hosted create pins the version and runs the installed initializer',
    () async {
      final calls = <({String executable, List<String> args, String cwd})>[];
      final output = StringBuffer();
      final errors = StringBuffer();
      final code = await runOdroe(
        ['create', target, '--odroe-version', '0.1.0-dev.1', '--offline'],
        output: output,
        errors: errors,
        createProjectInitializer: (_, _, _) =>
            throw StateError('checkout initializer'),
        createCommandRunner:
            (
              executable,
              arguments, {
              required workingDirectory,
              required out,
              required err,
              environment,
            }) async {
              calls.add((
                executable: executable,
                args: arguments,
                cwd: workingDirectory,
              ));
              if (calls.length == 2) _lock(workingDirectory);
              if (calls.length == 3) {
                out.writeln('Initialized in $workingDirectory.');
              }
              return 0;
            },
      );
      expect(code, 0, reason: '$errors');
      expect(calls, hasLength(3));
      expect(calls[1].args, containsAllInOrder(['pub', 'add', '--offline']));
      expect(jsonDecode(calls[1].args.last.substring('odroe:'.length)), {
        'version': '0.1.0-dev.1',
      });
      expect(calls[2].executable, Platform.resolvedExecutable);
      expect(calls[2].args, ['run', 'odroe', 'init', '--full-stack']);
      expect(calls[2].cwd, calls[1].cwd);
      expect(Directory(target).existsSync(), isTrue);
      expect(Directory(calls[2].cwd).existsSync(), isFalse);
      final finalTarget = Directory(target).resolveSymbolicLinksSync();
      expect('$output', contains('Initialized in $finalTarget.'));
      expect('$output', isNot(contains(calls[2].cwd)));
    },
  );

  for (final invalid in [
    '',
    'latest',
    'any',
    '^0.1.0',
    '>=0.1.0',
    '0.1',
    'v0.1.0',
    '01.1.0',
    '0.1.0 dev',
    '0.1.0\n',
  ]) {
    test(
      'rejects non-exact version ${jsonEncode(invalid)} before staging',
      () async {
        final errors = StringBuffer();
        expect(
          await runOdroe(
            ['create', target, '--odroe-version', invalid],
            output: StringBuffer(),
            errors: errors,
            createCommandRunner:
                (
                  _,
                  _, {
                  required workingDirectory,
                  required out,
                  required err,
                  environment,
                }) => throw StateError('ran process'),
          ),
          64,
        );
        expect('$errors', contains('exact'));
        expect(parent.listSync(), isEmpty);
      },
    );
  }

  test('rejects competing dependency sources before staging', () async {
    final errors = StringBuffer();
    expect(
      await runOdroe(
        [
          'create',
          target,
          '--odroe-path',
          Directory.current.path,
          '--odroe-version',
          '0.1.0-dev.1',
        ],
        output: StringBuffer(),
        errors: errors,
      ),
      64,
    );
    expect('$errors', contains('exactly one'));
    expect(parent.listSync(), isEmpty);
  });

  for (var failure = 1; failure <= 3; failure++) {
    test('hosted stage $failure failure removes only owned staging', () async {
      final sentinel = File(p.join(parent.path, 'user-data'))
        ..writeAsStringSync('keep');
      final errors = StringBuffer();
      final output = StringBuffer();
      var stage = 0;
      String? staging;
      final code = await runOdroe(
        ['create', target, '--odroe-version', '0.1.0-dev.1'],
        output: output,
        errors: errors,
        createCommandRunner:
            (
              _,
              arguments, {
              required workingDirectory,
              required out,
              required err,
              environment,
            }) async {
              stage++;
              staging ??= arguments.last;
              File(p.join(staging!, 'partial')).writeAsStringSync('owned');
              if (stage == 2) _lock(workingDirectory);
              if (stage == 3) out.writeln('Uncommitted initializer output');
              return stage == failure ? 7 : 0;
            },
      );
      expect(code, 7, reason: '$errors');
      expect('$errors', contains('Removed the incomplete staging path'));
      expect('$output', isNot(contains('Uncommitted initializer output')));
      expect(Directory(target).existsSync(), isFalse);
      expect(Directory(staging!).existsSync(), isFalse);
      expect(parent.listSync().map((e) => p.basename(e.path)), ['user-data']);
      expect(sentinel.readAsStringSync(), 'keep');
    });
  }

  for (final resolution in [('path', '0.1.0-dev.1'), ('hosted', '0.0.8')]) {
    test('rejects unexpected resolved package $resolution', () async {
      var calls = 0;
      final errors = StringBuffer();
      expect(
        await runOdroe(
          ['create', target, '--odroe-version', '0.1.0-dev.1'],
          output: StringBuffer(),
          errors: errors,
          createCommandRunner:
              (
                _,
                _, {
                required workingDirectory,
                required out,
                required err,
                environment,
              }) async {
                if (++calls == 2) {
                  _lock(
                    workingDirectory,
                    source: resolution.$1,
                    version: resolution.$2,
                  );
                }
                return 0;
              },
        ),
        1,
      );
      expect(calls, 2);
      expect('$errors', contains('hosted Odroe 0.1.0-dev.1'));
      expect(parent.listSync(), isEmpty);
    });
  }

  for (final kind in [
    'empty directory',
    'nonempty directory',
    'file',
    'symlink',
  ]) {
    test(
      'hosted create preserves an existing $kind',
      () async {
        final sentinel = File(p.join(parent.path, 'sentinel'))
          ..writeAsStringSync('keep');
        if (kind == 'file') {
          File(target).writeAsStringSync('keep target');
        } else if (kind == 'symlink') {
          Link(target).createSync(sentinel.path);
        } else {
          Directory(target).createSync();
          if (kind == 'nonempty directory') {
            File(p.join(target, 'owned')).writeAsStringSync('keep');
          }
        }
        final before = FileSystemEntity.typeSync(target, followLinks: false);
        final errors = StringBuffer();
        expect(
          await runOdroe(
            ['create', target, '--odroe-version', '0.1.0-dev.1'],
            output: StringBuffer(),
            errors: errors,
            createCommandRunner:
                (
                  _,
                  _, {
                  required workingDirectory,
                  required out,
                  required err,
                  environment,
                }) => throw StateError('ran process'),
          ),
          1,
        );
        expect('$errors', contains('will not overwrite'));
        expect(FileSystemEntity.typeSync(target, followLinks: false), before);
        expect(sentinel.readAsStringSync(), 'keep');
        if (kind == 'file') {
          expect(File(target).readAsStringSync(), 'keep target');
        }
        if (kind == 'nonempty directory') {
          expect(File(p.join(target, 'owned')).readAsStringSync(), 'keep');
        }
      },
      skip: kind == 'symlink' && Platform.isWindows
          ? 'Requires symlink privileges.'
          : false,
    );
  }

  test(
    'hosted initializer cannot replace a target created during resolution',
    () async {
      var calls = 0;
      final errors = StringBuffer();
      expect(
        await runOdroe(
          ['create', target, '--odroe-version', '0.1.0-dev.1'],
          output: StringBuffer(),
          errors: errors,
          createCommandRunner:
              (
                _,
                _, {
                required workingDirectory,
                required out,
                required err,
                environment,
              }) async {
                if (++calls == 2) _lock(workingDirectory);
                if (calls == 3) {
                  Directory(target).createSync();
                  File(p.join(target, 'user-data')).writeAsStringSync('keep');
                }
                return 0;
              },
        ),
        1,
      );
      expect('$errors', contains('appeared before'));
      expect(File(p.join(target, 'user-data')).readAsStringSync(), 'keep');
      expect(parent.listSync().map((e) => p.basename(e.path)), ['app']);
    },
  );
}

void _lock(
  String project, {
  String source = 'hosted',
  String version = '0.1.0-dev.1',
}) {
  File(p.join(project, 'pubspec.lock')).writeAsStringSync('''
packages:
  odroe:
    source: $source
    version: "$version"
''');
}
