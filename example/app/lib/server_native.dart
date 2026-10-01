import 'dart:async';
import 'dart:io';

import 'package:odroe/database_sqlite.dart';
import 'package:odroe/server.dart';

import 'routes.server.dart' as generated;

FutureOr<Server> createServer() => createNativeServer(
  databasePath:
      Platform.environment['ODROE_SQLITE_PATH'] ?? '.odroe/app.sqlite3',
  migrationsPath: Platform.environment['ODROE_MIGRATIONS_PATH'] ?? 'migrations',
);

Future<Server> createNativeServer({
  required String databasePath,
  String migrationsPath = 'migrations',
}) async {
  if (databasePath.isEmpty) {
    throw ArgumentError.value(
      databasePath,
      'databasePath',
      'must not be empty',
    );
  }
  if (migrationsPath.isEmpty) {
    throw ArgumentError.value(
      migrationsPath,
      'migrationsPath',
      'must not be empty',
    );
  }
  final migrations = readSqliteMigrations(migrationsPath);
  final databaseFile = File(databasePath).absolute;
  await databaseFile.parent.create(recursive: true);
  return _createServer(
    SqliteDatabase.open(databaseFile.path),
    migrations: migrations,
  );
}

Future<Server> _createServer(
  SqliteDatabase database, {
  required List<SqliteMigration> migrations,
}) async {
  try {
    await database.applyMigrations(migrations);
    return generated.createServer(
      modules: () => <DatabaseModule>[DatabaseModule.borrowed(database)],
      onClose: database.close,
    );
  } on Object {
    await database.close();
    rethrow;
  }
}
