import 'dart:async';
import 'dart:io';

import 'package:odroe/src/cli/build.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final root = Directory(arguments[0]);
  final mode = arguments[1];
  final ready = File(arguments[2]);
  final go = File(arguments[3]);
  final output = Directory(p.join(root.path, 'output'))..createSync();
  final bundle = Directory(p.join(output.path, 'server'));
  final stagedBundle = Directory(p.join(root.path, 'staging-$mode'));
  File(
      p.join(
        stagedBundle.path,
        'bin',
        Platform.isWindows ? 'server.exe' : 'server',
      ),
    )
    ..createSync(recursive: true)
    ..writeAsStringSync(mode);
  Directory(p.join(stagedBundle.path, 'lib')).createSync();
  File(
    p.join(stagedBundle.path, '.odroe-native-bundle'),
  ).writeAsStringSync('odroe-native-bundle-v1\n');
  if (mode == 'selected') {
    final stagedMigrations = Directory(p.join(stagedBundle.path, 'migrations'))
      ..createSync();
    File(
      p.join(stagedMigrations.path, '0001_selected.sql'),
    ).writeAsStringSync('SELECT 1;');
  }

  ready.writeAsStringSync('ready');
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!go.existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Publication barrier timed out.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  try {
    await replaceNativeBundle(
      stagedBundle: stagedBundle,
      bundle: bundle,
      lockFile: File(p.join(root.path, 'native-build.lock')),
    );
  } on FileSystemException catch (error) {
    if (mode == 'absent' &&
        error.message.contains(
          'A previous Native build bundled SQLite migrations.',
        )) {
      return;
    }
    rethrow;
  }
}
