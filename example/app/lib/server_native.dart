import 'dart:async';
import 'dart:io';

import 'package:odroe/database_sqlite.dart';
import 'package:odroe/server.dart';

import 'posts_database.dart';
import 'routes.server.dart' as generated;

FutureOr<Server> createServer() => createNativeServer(
  databasePath:
      Platform.environment['ODROE_SQLITE_PATH'] ?? '.odroe/app.sqlite3',
);

Future<Server> createNativeServer({required String databasePath}) async {
  if (databasePath.isEmpty) {
    throw ArgumentError.value(
      databasePath,
      'databasePath',
      'must not be empty',
    );
  }
  final databaseFile = File(databasePath).absolute;
  await databaseFile.parent.create(recursive: true);
  return _createServer(SqliteDatabase.open(databaseFile.path));
}

Future<Server> _createServer(SqliteDatabase database) async {
  try {
    await initializePostsDatabase(database);
    return generated.createServer(
      modules: () => <DatabaseModule>[DatabaseModule.borrowed(database)],
      onClose: database.close,
    );
  } on Object {
    await database.close();
    rethrow;
  }
}
