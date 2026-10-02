import 'dart:io';

import 'package:path/path.dart' as p;

final _migrationName = RegExp(r'^([0-9]{4,})_([a-z0-9]+(?:_[a-z0-9]+)*)\.sql$');

/// One append-only SQLite migration loaded from a numbered SQL file.
final class SqliteMigration {
  /// Creates a migration and validates its D1-compatible file [name].
  factory SqliteMigration({required String name, required String sql}) {
    final match = _migrationName.firstMatch(name);
    if (match == null) {
      throw FormatException(
        'SQLite migration names must match NNNN_snake_case.sql: $name',
      );
    }
    final version = int.parse(match.group(1)!);
    if (version == 0) {
      throw FormatException('SQLite migration versions must start at 0001.');
    }
    if (sql.contains('\u0000')) {
      throw FormatException('SQLite migration SQL cannot contain NUL bytes.');
    }
    return SqliteMigration._(version: version, name: name, sql: sql);
  }

  const SqliteMigration._({
    required this.version,
    required this.name,
    required this.sql,
  });

  /// Numeric prefix used to order the migration.
  final int version;

  /// File name recorded in the native SQLite migration history.
  final String name;

  /// Complete SQL script executed as one migration.
  final String sql;
}

/// A native SQLite migration could not be applied or verified safely.
final class SqliteMigrationException implements Exception {
  /// Creates a migration failure without exposing the migration SQL.
  const SqliteMigrationException(this.message, {this.migration, this.cause});

  /// Human-readable failure description.
  final String message;

  /// Migration file associated with the failure, when known.
  final String? migration;

  /// Original database failure, when available.
  final Object? cause;

  @override
  String toString() {
    final name = migration;
    return name == null
        ? 'SqliteMigrationException: $message'
        : 'SqliteMigrationException($name): $message';
  }
}

/// Reads top-level `NNNN_snake_case.sql` files from [directoryPath].
///
/// The returned migrations are ordered by their numeric prefix. Other files
/// are ignored, while invalid `.sql` entries and duplicate versions fail
/// before a database is changed.
List<SqliteMigration> readSqliteMigrations(String directoryPath) {
  if (directoryPath.isEmpty) {
    throw ArgumentError.value(
      directoryPath,
      'directoryPath',
      'must not be empty',
    );
  }
  final directory = Directory(directoryPath).absolute;
  if (!directory.existsSync()) {
    throw FileSystemException(
      'SQLite migration directory does not exist.',
      directory.path,
    );
  }

  final migrations = <SqliteMigration>[];
  for (final entity in directory.listSync(followLinks: false)) {
    final name = p.basename(entity.path);
    if (name.startsWith('.') || !name.endsWith('.sql')) continue;
    if (entity is! File) {
      throw FormatException(
        'SQLite migration must be a top-level regular file: $name',
      );
    }
    migrations.add(SqliteMigration(name: name, sql: entity.readAsStringSync()));
  }
  migrations.sort((left, right) {
    final version = left.version.compareTo(right.version);
    return version == 0 ? left.name.compareTo(right.name) : version;
  });
  for (var index = 1; index < migrations.length; index++) {
    if (migrations[index - 1].version == migrations[index].version) {
      throw FormatException(
        'SQLite migration version ${migrations[index].version} is duplicated.',
      );
    }
  }
  return List<SqliteMigration>.unmodifiable(migrations);
}
