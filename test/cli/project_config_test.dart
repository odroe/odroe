import 'dart:io';

import 'package:odroe/src/cli/project.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('project config selects an application-owned SQLite history', () async {
    final project = await _project();
    addTearDown(() => project.delete(recursive: true));

    expect(
      CliProject.fromRoot(project.path).configuredSqliteMigrations,
      isNull,
    );

    File(
      p.join(project.path, 'odroe.yaml'),
    ).writeAsStringSync('sqlite_migrations: database/migrations\n');

    expect(
      CliProject.fromRoot(project.path).configuredSqliteMigrations,
      p.join('database', 'migrations'),
    );
  });

  test('project config rejects ambiguous or unsafe values', () async {
    final project = await _project();
    addTearDown(() => project.delete(recursive: true));
    final config = File(p.join(project.path, 'odroe.yaml'));

    for (final source in <String>[
      '',
      '- migrations\n',
      'unknown: migrations\n',
      'sqlite_migrations: null\n',
      "sqlite_migrations: ''\n",
      'sqlite_migrations: ../migrations\n',
      'sqlite_migrations: ${Directory.systemTemp.absolute.path}\n',
    ]) {
      config.writeAsStringSync(source);
      expect(
        () => CliProject.fromRoot(project.path),
        throwsA(anyOf(isA<FormatException>(), isA<FileSystemException>())),
        reason: source,
      );
    }
  });

  test(
    'project config rejects symbolic links',
    () async {
      final project = await _project();
      final outside = await Directory.systemTemp.createTemp(
        'odroe_project_config_outside_',
      );
      addTearDown(() => project.delete(recursive: true));
      addTearDown(() => outside.delete(recursive: true));

      final outsideConfig = File(p.join(outside.path, 'config.yaml'))
        ..writeAsStringSync('sqlite_migrations: migrations\n');
      Link(
        p.join(project.path, 'odroe.yaml'),
      ).createSync(outsideConfig.absolute.path);
      expect(
        () => CliProject.fromRoot(project.path),
        throwsA(isA<FileSystemException>()),
      );

      Link(p.join(project.path, 'odroe.yaml')).deleteSync();
      File(
        p.join(project.path, 'odroe.yaml'),
      ).writeAsStringSync('sqlite_migrations: linked/migrations\n');
      Link(p.join(project.path, 'linked')).createSync(outside.path);
      expect(
        () => CliProject.fromRoot(project.path),
        throwsA(isA<FormatException>()),
      );
    },
    skip: Platform.isWindows
        ? 'Symbolic link permissions vary on Windows.'
        : false,
  );
}

Future<Directory> _project() async {
  final project = await Directory.systemTemp.createTemp(
    'odroe_project_config_',
  );
  File(
    p.join(project.path, 'pubspec.yaml'),
  ).writeAsStringSync('name: project_config_fixture\n');
  return project;
}
