import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../support/dart_command_lock.dart';

void main() {
  test('create runs two Flutter commands and initializes in process', () async {
    final parent = await Directory.systemTemp.createTemp('odroe_create_test_');
    addTearDown(() => parent.delete(recursive: true));
    final target = p.join(parent.path, 'my app');
    final resolvedTarget = p.join(parent.resolveSymbolicLinksSync(), 'my app');
    final calls = <_Command>[];
    final output = StringBuffer();
    final errors = StringBuffer();
    Directory? initializedProject;

    final code = await runOdroe(
      <String>[
        'create',
        target,
        '--platforms',
        'web,android,web',
        '--org',
        'dev.odroe',
        '--project-name',
        'my_app',
        '--odroe-path',
        Directory.current.path,
        '--offline',
      ],
      output: output,
      errors: errors,
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
              arguments: List<String>.of(arguments),
              workingDirectory: workingDirectory,
            ));
            return 0;
          },
      createProjectInitializer: (project, out, err) {
        initializedProject = project;
        out.writeln('Initialized in ${project.path}.');
        return true;
      },
    );

    expect(code, 0, reason: errors.toString());
    expect(errors, isEmpty);
    expect(calls, hasLength(2));
    expect(
      p.basenameWithoutExtension(calls[0].executable),
      Platform.isWindows ? 'dart' : 'flutter',
    );
    expect(
      calls[0].arguments,
      containsAllInOrder(<String>[
        'create',
        '--empty',
        '--no-pub',
        '--no-overwrite',
        '--platforms=web,android',
        '--org=dev.odroe',
        '--project-name=my_app',
      ]),
    );
    final staging = calls[0].arguments.last;
    expect(p.dirname(staging), p.dirname(resolvedTarget));
    expect(p.basename(staging), startsWith('.odroe-create-'));
    expect(calls[0].workingDirectory, p.dirname(resolvedTarget));
    expect(
      calls[1].arguments,
      containsAllInOrder(<String>['pub', 'add', '--offline']),
    );
    final descriptor = calls[1].arguments.last;
    expect(descriptor, startsWith('odroe:'));
    expect(jsonDecode(descriptor.substring('odroe:'.length)), <String, Object?>{
      'path': p.relative(
        Directory.current.resolveSymbolicLinksSync(),
        from: resolvedTarget,
      ),
    });
    expect(calls[1].workingDirectory, staging);
    expect(initializedProject?.path, staging);
    expect(output.toString(), contains('Odroe starter initialization...'));
    expect(output.toString(), contains('Initialized in $resolvedTarget.'));
    expect(output.toString(), isNot(contains('Initialized in $staging.')));
    expect(output.toString(), contains('Created the full-stack Odroe'));
    expect(Directory(target).existsSync(), isTrue);
    expect(Directory(staging).existsSync(), isFalse);
  });

  test('create rolls back every failed subprocess stage', () async {
    for (var failedStage = 0; failedStage < 2; failedStage++) {
      final parent = await Directory.systemTemp.createTemp(
        'odroe_create_failure_',
      );
      addTearDown(() {
        if (parent.existsSync()) parent.deleteSync(recursive: true);
      });
      final target = p.join(parent.path, 'app_$failedStage');
      var stage = 0;
      String? staging;
      final errors = StringBuffer();

      final code = await runOdroe(
        <String>['create', '--odroe-path', Directory.current.path, target],
        output: StringBuffer(),
        errors: errors,
        createCommandRunner:
            (
              executable,
              arguments, {
              required workingDirectory,
              required out,
              required err,
              environment,
            }) async {
              staging ??= arguments.last;
              File(
                p.join(staging!, 'partial-$stage'),
              ).writeAsStringSync('partial');
              return stage++ == failedStage ? 7 : 0;
            },
      );

      expect(code, 7, reason: 'failedStage=$failedStage');
      expect(Directory(target).existsSync(), isFalse);
      expect(errors.toString(), contains('failed.'));
      expect(
        errors.toString(),
        contains('Removed the incomplete staging path'),
      );
    }
  });

  test('create rolls back when its in-process initializer rejects', () async {
    final parent = await Directory.systemTemp.createTemp(
      'odroe_create_initializer_failure_',
    );
    addTearDown(() => parent.delete(recursive: true));
    final target = p.join(parent.path, 'app');
    final output = StringBuffer();
    final errors = StringBuffer();
    Directory? staging;

    final code = await runOdroe(
      <String>['create', '--odroe-path', Directory.current.path, target],
      output: output,
      errors: errors,
      createCommandRunner: _successfulCreateCommand,
      createProjectInitializer: (project, out, err) {
        staging = project;
        File(p.join(project.path, 'partial')).writeAsStringSync('partial');
        out.writeln('Rejected initializer output.');
        return false;
      },
    );

    expect(code, 1);
    expect(FileSystemEntity.typeSync(target), FileSystemEntityType.notFound);
    expect(
      FileSystemEntity.typeSync(staging!.path),
      FileSystemEntityType.notFound,
    );
    expect(errors.toString(), contains('starter initialization failed'));
    expect(errors.toString(), contains('Removed the incomplete staging path'));
    expect(output.toString(), isNot(contains('Rejected initializer output')));
  });

  test('create rolls back when its in-process initializer throws', () async {
    final parent = await Directory.systemTemp.createTemp(
      'odroe_create_initializer_throw_',
    );
    addTearDown(() => parent.delete(recursive: true));
    final target = p.join(parent.path, 'app');
    final errors = StringBuffer();
    Directory? staging;
    final failure = StateError('initializer stopped');

    await expectLater(
      runOdroe(
        <String>['create', '--odroe-path', Directory.current.path, target],
        output: StringBuffer(),
        errors: errors,
        createCommandRunner: _successfulCreateCommand,
        createProjectInitializer: (project, out, err) {
          staging = project;
          File(p.join(project.path, 'partial')).writeAsStringSync('partial');
          throw failure;
        },
      ),
      throwsA(same(failure)),
    );

    expect(FileSystemEntity.typeSync(target), FileSystemEntityType.notFound);
    expect(
      FileSystemEntity.typeSync(staging!.path),
      FileSystemEntityType.notFound,
    );
    expect(errors.toString(), contains('Removed the incomplete staging path'));
  });

  test('create rolls back when its command runner throws', () async {
    final parent = await Directory.systemTemp.createTemp('odroe_create_throw_');
    addTearDown(() => parent.delete(recursive: true));
    final target = p.join(parent.path, 'app');
    final errors = StringBuffer();

    await expectLater(
      runOdroe(
        <String>['create', '--odroe-path', Directory.current.path, target],
        output: StringBuffer(),
        errors: errors,
        createCommandRunner:
            (
              executable,
              arguments, {
              required workingDirectory,
              required out,
              required err,
              environment,
            }) async => throw StateError('runner stopped'),
      ),
      throwsStateError,
    );

    expect(Directory(target).existsSync(), isFalse);
    expect(errors.toString(), contains('Removed the incomplete staging path'));
  });

  test('create rejects a staged project resolving another checkout', () async {
    final parent = await Directory.systemTemp.createTemp(
      'odroe_create_checkout_mismatch_',
    );
    addTearDown(() => parent.delete(recursive: true));
    final otherOdroe = Directory(p.join(parent.path, 'other_odroe', 'lib'))
      ..createSync(recursive: true);
    File(p.join(otherOdroe.path, 'odroe.dart')).writeAsStringSync('library;\n');
    final otherRoot = otherOdroe.parent;
    final target = p.join(parent.path, 'app');
    final errors = StringBuffer();
    String? staging;

    final code = await runOdroe(
      <String>['create', '--odroe-path', Directory.current.path, target],
      output: StringBuffer(),
      errors: errors,
      createCommandRunner:
          (
            executable,
            arguments, {
            required workingDirectory,
            required out,
            required err,
            environment,
          }) async {
            if (staging == null) {
              staging = arguments.last;
              File(p.join(staging!, '.metadata')).writeAsStringSync('''
project_type: app
''');
              File(p.join(staging!, 'pubspec.yaml')).writeAsStringSync('''
name: app
dependencies:
  flutter:
    sdk: flutter
  odroe:
    path: unused
''');
              final dartTool = Directory(p.join(staging!, '.dart_tool'))
                ..createSync();
              File(
                p.join(dartTool.path, 'package_config.json'),
              ).writeAsStringSync(
                jsonEncode(<String, Object?>{
                  'configVersion': 2,
                  'packages': <Object?>[
                    <String, Object?>{
                      'name': 'odroe',
                      'rootUri': otherRoot.uri.toString(),
                      'packageUri': 'lib/',
                      'languageVersion': '3.10',
                    },
                  ],
                }),
              );
            }
            return 0;
          },
    );

    expect(code, 1);
    expect(errors.toString(), contains('resolves a different Odroe checkout'));
    expect(FileSystemEntity.typeSync(target), FileSystemEntityType.notFound);
    expect(FileSystemEntity.typeSync(staging!), FileSystemEntityType.notFound);
  });

  test('create never touches an existing target', () async {
    final parent = await Directory.systemTemp.createTemp(
      'odroe_create_existing_',
    );
    addTearDown(() => parent.delete(recursive: true));
    final target = Directory(p.join(parent.path, 'app'))..createSync();
    final sentinel = File(p.join(target.path, 'sentinel'))
      ..writeAsStringSync('owned');
    var called = false;
    final errors = StringBuffer();

    final code = await runOdroe(
      <String>['create', '--odroe-path', Directory.current.path, target.path],
      output: StringBuffer(),
      errors: errors,
      createCommandRunner:
          (
            executable,
            arguments, {
            required workingDirectory,
            required out,
            required err,
            environment,
          }) async {
            called = true;
            return 0;
          },
    );

    expect(code, 1);
    expect(called, isFalse);
    expect(sentinel.readAsStringSync(), 'owned');
    expect(errors.toString(), contains('will not overwrite'));
    expect(
      errors.toString(),
      isNot(contains('Removed the incomplete staging')),
    );
  });

  test('create validates arguments before reserving the target', () async {
    final parent = await Directory.systemTemp.createTemp(
      'odroe_create_invalid_',
    );
    addTearDown(() => parent.delete(recursive: true));
    final target = p.join(parent.path, 'app');
    var called = false;
    Future<int> run(List<String> arguments, StringBuffer errors) => runOdroe(
      arguments,
      output: StringBuffer(),
      errors: errors,
      createCommandRunner:
          (
            executable,
            arguments, {
            required workingDirectory,
            required out,
            required err,
            environment,
          }) async {
            called = true;
            return 0;
          },
    );

    final missingSourceErrors = StringBuffer();
    expect(await run(<String>['create', target], missingSourceErrors), 64);
    expect(missingSourceErrors.toString(), contains('--odroe-path'));

    final platformErrors = StringBuffer();
    expect(
      await run(<String>[
        'create',
        '--odroe-path',
        Directory.current.path,
        '--platforms',
        'web,watchos',
        target,
      ], platformErrors),
      64,
    );
    expect(platformErrors.toString(), contains('watchos'));

    final nameErrors = StringBuffer();
    expect(
      await run(<String>[
        'create',
        '--odroe-path',
        Directory.current.path,
        '--project-name',
        'Bad-Name',
        target,
      ], nameErrors),
      64,
    );
    expect(nameErrors.toString(), contains('Invalid Flutter project name'));
    expect(called, isFalse);
    expect(FileSystemEntity.typeSync(target), FileSystemEntityType.notFound);
  });

  test('create preserves a target that appears before publication', () async {
    final parent = await Directory.systemTemp.createTemp(
      'odroe_create_publish_race_',
    );
    addTearDown(() => parent.delete(recursive: true));
    final target = p.join(parent.path, 'app');
    final errors = StringBuffer();

    final code = await runOdroe(
      <String>['create', '--odroe-path', Directory.current.path, target],
      output: StringBuffer(),
      errors: errors,
      createCommandRunner: _successfulCreateCommand,
      createProjectInitializer: (project, out, err) {
        final external = Directory(target)..createSync();
        File(p.join(external.path, 'sentinel')).writeAsStringSync('owned');
        return true;
      },
    );

    expect(code, 1);
    expect(File(p.join(target, 'sentinel')).readAsStringSync(), 'owned');
    expect(errors.toString(), contains('appeared before'));
    expect(
      parent.listSync().where(
        (entity) => p.basename(entity.path).startsWith('.odroe-create-'),
      ),
      isEmpty,
    );
  });

  test('create preserves spaces and Unicode in a path descriptor', () async {
    final parent = await Directory.systemTemp.createTemp('odroe_create_path_');
    addTearDown(() => parent.delete(recursive: true));
    final source = Directory(p.join(parent.path, 'odroe source 你好'))
      ..createSync();
    File(
      p.join(source.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: odroe\n');
    File(p.join(source.path, 'lib', 'odroe.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('library;\n');
    final target = p.join(parent.path, 'new app 你好');
    String? descriptor;

    expect(
      await runOdroe(
        <String>[
          'create',
          '--project-name',
          'new_app',
          '--odroe-path',
          source.path,
          target,
        ],
        output: StringBuffer(),
        errors: StringBuffer(),
        createCommandRunner:
            (
              executable,
              arguments, {
              required workingDirectory,
              required out,
              required err,
              environment,
            }) async {
              if (arguments.contains('pub') && arguments.contains('add')) {
                descriptor = arguments.last;
              }
              return 0;
            },
        createProjectInitializer: _succeedingCreateInitializer,
      ),
      0,
    );
    expect(
      jsonDecode(descriptor!.substring('odroe:'.length)),
      <String, Object?>{
        'path': p.relative(
          source.resolveSymbolicLinksSync(),
          from: Directory(target).resolveSymbolicLinksSync(),
        ),
      },
    );
  });

  test('create defaults to Android, iOS, and Web', () async {
    final parent = await Directory.systemTemp.createTemp(
      'odroe_create_defaults_',
    );
    addTearDown(() => parent.delete(recursive: true));
    final target = p.join(parent.path, 'app');
    List<String>? flutterCreate;

    expect(
      await runOdroe(
        <String>['create', '--odroe-path', Directory.current.path, target],
        output: StringBuffer(),
        errors: StringBuffer(),
        createCommandRunner:
            (
              executable,
              arguments, {
              required workingDirectory,
              required out,
              required err,
              environment,
            }) async {
              flutterCreate ??= List<String>.of(arguments);
              return 0;
            },
        createProjectInitializer: _succeedingCreateInitializer,
      ),
      0,
    );
    expect(flutterCreate, contains('--platforms=android,ios,web'));
  });

  test('create help exposes its product contract', () async {
    final rootHelp = StringBuffer();
    final createHelp = StringBuffer();
    final errors = StringBuffer();

    expect(await runOdroe(<String>['--help'], output: rootHelp), 0);
    expect(rootHelp.toString(), contains('create    Create a new full-stack'));
    expect(await runOdroe(<String>['create', '--help'], output: createHelp), 0);
    expect(createHelp.toString(), contains('--platforms'));
    expect(createHelp.toString(), contains('--odroe-path'));
    expect(createHelp.toString(), contains('--odroe-version'));
    expect(
      await runOdroe(
        <String>['create'],
        output: StringBuffer(),
        errors: errors,
      ),
      64,
    );
    expect(errors.toString(), contains('exactly one target'));
  });

  test(
    'create removes only its staging path after an interrupt',
    () => withDartCommandLock(() async {
      final parent = await Directory.systemTemp.createTemp(
        'odroe_create_interrupt_',
      );
      addTearDown(() => parent.delete(recursive: true));
      final target = p.join(parent.path, 'app');
      final marker = File(p.join(parent.path, 'ready'));
      final process = await Process.start(dartExecutable, <String>[
        'run',
        'test/fixtures/create_interruption.dart',
        target,
        Directory.current.path,
        marker.path,
      ]);
      addTearDown(() => process.kill(ProcessSignal.sigkill));
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();

      await _waitForFile(marker);
      expect(process.kill(ProcessSignal.sigint), isTrue);
      expect(await process.exitCode.timeout(const Duration(seconds: 10)), 130);
      expect(await output, contains('Flutter project creation'));
      expect(await errors, contains('Removed the incomplete staging path'));
      expect(FileSystemEntity.typeSync(target), FileSystemEntityType.notFound);
      expect(
        parent.listSync().where(
          (entity) => p.basename(entity.path).startsWith('.odroe-create-'),
        ),
        isEmpty,
      );
    }),
    timeout: const Timeout(Duration(minutes: 4)),
    skip: Platform.isWindows
        ? 'Windows Process.kill does not emit a console SIGINT event.'
        : false,
  );

  test(
    'create does not publish after an initializer interrupt',
    () => withDartCommandLock(() async {
      for (final initializerResult in <String>['success', 'failure']) {
        final parent = await Directory.systemTemp.createTemp(
          'odroe_create_initializer_interrupt_',
        );
        addTearDown(() => parent.delete(recursive: true));
        final target = p.join(parent.path, 'app');
        final marker = File(p.join(parent.path, 'ready'));
        final process = await Process.start(dartExecutable, <String>[
          'run',
          'test/fixtures/create_interruption.dart',
          target,
          Directory.current.path,
          marker.path,
          'initializer-$initializerResult',
        ]);
        addTearDown(() => process.kill(ProcessSignal.sigkill));
        final output = process.stdout.transform(utf8.decoder).join();
        final errors = process.stderr.transform(utf8.decoder).join();

        await _waitForFile(marker);
        expect(process.kill(ProcessSignal.sigint), isTrue);
        expect(
          await process.exitCode.timeout(const Duration(seconds: 10)),
          130,
          reason: initializerResult,
        );
        expect(await output, contains('Odroe starter initialization'));
        expect(await output, isNot(contains('Completed initializer output')));
        expect(await errors, contains('Removed the incomplete staging path'));
        expect(
          FileSystemEntity.typeSync(target),
          FileSystemEntityType.notFound,
        );
        expect(
          parent.listSync().where(
            (entity) => p.basename(entity.path).startsWith('.odroe-create-'),
          ),
          isEmpty,
        );
      }
    }),
    timeout: const Timeout(Duration(minutes: 4)),
    skip: Platform.isWindows
        ? 'Windows Process.kill does not emit a console SIGINT event.'
        : false,
  );

  test(
    'create emits an analyzable real Flutter full-stack application',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'odroe_create_real_',
      );
      addTearDown(() => parent.delete(recursive: true));
      final target = p.join(parent.path, 'real_app');
      final output = StringBuffer();
      final errors = StringBuffer();
      final calls = <_Command>[];

      await withDartCommandLock(() async {
        final code = await runOdroe(
          <String>[
            'create',
            '--platforms',
            'web',
            '--project-name',
            'real_app',
            '--odroe-path',
            Directory.current.path,
            '--offline',
            target,
          ],
          output: output,
          errors: errors,
          createCommandRunner:
              (
                executable,
                arguments, {
                required workingDirectory,
                required out,
                required err,
                environment,
              }) {
                calls.add((
                  executable: executable,
                  arguments: List<String>.of(arguments),
                  workingDirectory: workingDirectory,
                ));
                return _runRealCreateFixtureCommand(
                  executable,
                  arguments,
                  workingDirectory: workingDirectory,
                  out: out,
                  err: err,
                  environment: environment,
                );
              },
        );

        expect(code, 0, reason: '${errors.toString()}\n${output.toString()}');
        expect(calls, hasLength(2));
        expect(calls[0].arguments, contains('create'));
        expect(
          calls[1].arguments,
          containsAllInOrder(<String>['pub', 'add', '--offline']),
        );
        expect(
          calls.any(
            (call) =>
                call.arguments.length >= 2 &&
                call.arguments[0] == 'run' &&
                call.arguments[1] == 'odroe',
          ),
          isFalse,
        );
        final main = File(
          p.join(target, 'lib', 'main.dart'),
        ).readAsStringSync();
        expect(
          RegExp(r"import 'package:odroe/").allMatches(main),
          hasLength(1),
        );
        expect(main, contains("import 'package:odroe/odroe_flutter.dart';"));
        expect(main, contains('QueryModule()'));
        expect(
          File(p.join(target, 'lib', 'routes.server.dart')).existsSync(),
          isTrue,
        );
        expect(File(p.join(target, 'wrangler.jsonc')).existsSync(), isTrue);
        expect(
          File(p.join(target, 'odroe.yaml')).readAsStringSync(),
          'sqlite_migrations: migrations\n',
        );
        final pubspec =
            loadYaml(File(p.join(target, 'pubspec.yaml')).readAsStringSync())
                as YamlMap;
        expect(pubspec.containsKey('hooks'), isFalse);
        final dependencies = pubspec['dependencies'] as YamlMap;
        final odroeDependency = dependencies['odroe'] as YamlMap;
        final declaredRoot = Directory(
          p.join(target, odroeDependency['path'] as String),
        ).resolveSymbolicLinksSync();
        expect(declaredRoot, Directory.current.resolveSymbolicLinksSync());
        final packageConfig = File(
          p.join(target, '.dart_tool', 'package_config.json'),
        );
        final config = jsonDecode(packageConfig.readAsStringSync()) as Map;
        final odroePackage = (config['packages'] as List)
            .cast<Map>()
            .singleWhere((package) => package['name'] == 'odroe');
        final resolvedRoot = Directory.fromUri(
          packageConfig.uri.resolve(odroePackage['rootUri'] as String),
        ).resolveSymbolicLinksSync();
        expect(resolvedRoot, Directory.current.resolveSymbolicLinksSync());

        final analyze = await Process.run(dartExecutable, const <String>[
          'analyze',
          '--fatal-infos',
        ], workingDirectory: target);
        expect(
          analyze.exitCode,
          0,
          reason: '${analyze.stdout}\n${analyze.stderr}',
        );
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<int> _runRealCreateFixtureCommand(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required StringSink out,
  required StringSink err,
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  out.write(result.stdout);
  err.write(result.stderr);
  return result.exitCode;
}

Future<int> _successfulCreateCommand(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required StringSink out,
  required StringSink err,
  Map<String, String>? environment,
}) async => 0;

bool _succeedingCreateInitializer(
  Directory project,
  StringSink out,
  StringSink err,
) => true;

typedef _Command = ({
  String executable,
  List<String> arguments,
  String workingDirectory,
});

Future<void> _waitForFile(File file) async {
  for (var attempt = 0; attempt < 1200; attempt++) {
    if (file.existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('Timed out waiting for ${file.path}.');
}
