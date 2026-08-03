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
  final staging = Directory(p.join(root.path, 'staging-$mode'))..createSync();
  final artifact = File(p.join(output.path, 'server'));
  final stagedArtifact = File(p.join(staging.path, 'server'))
    ..writeAsStringSync(mode);
  final migrations = Directory(p.join(output.path, 'migrations'));
  final stagedMigrations = mode == 'selected'
      ? (Directory(p.join(staging.path, 'migrations'))..createSync())
      : null;
  if (stagedMigrations != null) {
    File(
      p.join(stagedMigrations.path, '.odroe-native-migrations'),
    ).writeAsStringSync('server\n');
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
      stagedArtifact: stagedArtifact,
      stagedMigrations: stagedMigrations,
      artifact: artifact,
      migrations: migrations,
      lockFile: File(p.join(root.path, 'native-build.lock')),
      expectedMigrationOwner: stagedMigrations == null ? null : 'server\n',
    );
  } on FileSystemException {
    if (mode == 'absent') return;
    rethrow;
  }
}
