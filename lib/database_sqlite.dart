/// Native SQLite support that enables and verifies foreign-key enforcement
/// when opening each connection, with append-only migration support.
library;

export 'database.dart';
export 'src/database_sqlite/database.dart' show SqliteDatabase;
export 'src/database_sqlite/migration.dart'
    show SqliteMigration, SqliteMigrationException, readSqliteMigrations;
