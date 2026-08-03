import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/dart_command_lock.dart';
import '../support/process.dart';

void main() {
  test(
    'router entrypoint isolates Dart code but not the package SQLite hook',
    () async {
      final odroe = Directory.current.absolute;
      final state = await Directory.systemTemp.createTemp('odroe-router-cost-');
      final target = File(
        p.join(
          odroe.path,
          '.dart_tool',
          'odroe',
          'router-cost-$pid-${DateTime.now().microsecondsSinceEpoch}.dart',
        ),
      );
      target
        ..createSync(recursive: true)
        ..writeAsStringSync('''
import 'package:odroe/router.dart';

void main() => print(const NoParams());
''');
      addTearDown(() async {
        if (target.existsSync()) target.deleteSync();
        if (state.existsSync()) await state.delete(recursive: true);
      });
      final output = p.join(state.path, 'build');
      final depfile = File(p.join(state.path, 'probe.d'));

      final build = await withDartCommandLock(
        () => runTestProcess(dartExecutable, <String>[
          'build',
          'cli',
          '--target',
          target.path,
          '--output',
          output,
          '--depfile',
          depfile.path,
          '--verbosity',
          'warning',
        ], timeout: const Duration(minutes: 2)),
      );
      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');

      final dependencies = depfile.readAsStringSync();
      expect(
        dependencies,
        contains(p.join(odroe.path, 'lib', 'src', 'router', 'codec.dart')),
      );
      for (final source in <String>[
        'cli',
        'database',
        'database_d1',
        'database_mysql',
        'database_postgres',
        'database_sqlite',
        'router_compiler',
      ]) {
        expect(
          dependencies,
          isNot(contains(p.join(odroe.path, 'lib', 'src', source))),
          reason: source,
        );
      }

      final libraries = Directory(
        p.join(output, 'bundle', 'lib'),
      ).listSync(recursive: true).whereType<File>();
      expect(
        libraries.any(
          (file) => p.basename(file.path).toLowerCase().contains('sqlite'),
        ),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
