import 'dart:async';

import 'package:odroe/database_sqlite.dart';
import 'package:odroe/server.dart';

import 'posts_database.dart';
import 'routes.server.dart' as generated;

FutureOr<Server> createServer() => _createServer();

Future<Server> _createServer() async {
  final database = SqliteDatabase.openInMemory();
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
