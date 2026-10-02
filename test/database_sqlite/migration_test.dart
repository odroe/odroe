import 'dart:io';
import 'dart:isolate';

import 'package:odroe/database_sqlite.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

void main() {
  group('readSqliteMigrations', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('odroe-migrations-');
    });

    tearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });

    test('loads top-level SQL files in numeric order', () {
      File(
        p.join(directory.path, '0002_add_index.sql'),
      ).writeAsStringSync('CREATE INDEX records_name ON records(name);');
      File(
        p.join(directory.path, '0001_create_records.sql'),
      ).writeAsStringSync('CREATE TABLE records (name TEXT);');
      File(p.join(directory.path, 'README.md')).writeAsStringSync('ignored');
      final nested = Directory(p.join(directory.path, 'nested'))..createSync();
      File(
        p.join(nested.path, '0003_nested.sql'),
      ).writeAsStringSync('SELECT 1;');

      final migrations = readSqliteMigrations(directory.path);

      expect(migrations.map((migration) => migration.name), <String>[
        '0001_create_records.sql',
        '0002_add_index.sql',
      ]);
      expect(migrations.map((migration) => migration.version), <int>[1, 2]);
      expect(migrations.first.sql, 'CREATE TABLE records (name TEXT);');
    });

    test('rejects invalid names and duplicate versions', () {
      File(
        p.join(directory.path, '1_invalid.sql'),
      ).writeAsStringSync('SELECT 1;');
      expect(
        () => readSqliteMigrations(directory.path),
        throwsA(isA<FormatException>()),
      );

      File(p.join(directory.path, '1_invalid.sql')).deleteSync();
      File(
        p.join(directory.path, '0001_first.sql'),
      ).writeAsStringSync('SELECT 1;');
      File(
        p.join(directory.path, '0001_second.sql'),
      ).writeAsStringSync('SELECT 2;');
      expect(
        () => readSqliteMigrations(directory.path),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects missing and empty paths', () {
      expect(
        () => readSqliteMigrations(p.join(directory.path, 'missing')),
        throwsA(isA<FileSystemException>()),
      );
      expect(() => readSqliteMigrations(''), throwsA(isA<ArgumentError>()));
    });

    test('rejects SQL containing NUL before it reaches SQLite', () {
      expect(
        () => SqliteMigration(name: '0001_nul.sql', sql: 'SELECT 1;\u0000DROP'),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'rejects a symbolic-link migration',
      () {
        final target = File(p.join(directory.path, 'target.sql'))
          ..writeAsStringSync('SELECT 1;');
        Link(p.join(directory.path, '0001_linked.sql')).createSync(target.path);

        expect(
          () => readSqliteMigrations(directory.path),
          throwsA(isA<FormatException>()),
        );
      },
      skip: Platform.isWindows
          ? 'Symbolic link permissions vary on Windows.'
          : false,
    );
  });

  group('SqliteDatabase.applyMigrations', () {
    late SqliteDatabase database;

    setUp(() {
      database = SqliteDatabase.openInMemory();
    });

    tearDown(() => database.close());

    test('applies complete scripts once and adds later migrations', () async {
      final first = _migration('0001_create_records.sql', '''
CREATE TABLE records (id INTEGER PRIMARY KEY, name TEXT NOT NULL) STRICT;
INSERT INTO records (id, name) VALUES (1, 'Odroe 中文 👋');
CREATE INDEX records_name ON records(name);
''');
      final second = _migration('0002_add_slug.sql', '''
ALTER TABLE records ADD COLUMN slug TEXT NOT NULL DEFAULT '';
UPDATE records SET slug = 'odroe' WHERE id = 1;
''');

      expect(await database.applyMigrations(<SqliteMigration>[first]), 1);
      expect(await database.applyMigrations(<SqliteMigration>[first]), 0);
      expect(
        await _text(database, 'SELECT name FROM records WHERE id = 1'),
        'Odroe 中文 👋',
      );
      expect(
        await _integer(
          database,
          "SELECT count(*) FROM sqlite_master WHERE name = 'records_name'",
        ),
        1,
      );

      expect(
        await database.applyMigrations(<SqliteMigration>[first, second]),
        1,
      );
      expect(
        await _text(database, 'SELECT slug FROM records WHERE id = 1'),
        'odroe',
      );
      expect(
        await _text(
          database,
          'SELECT sql FROM _odroe_migrations WHERE version = 2',
        ),
        second.sql,
      );
    });

    test('enforces foreign keys declared by a migration', () async {
      final migration = _migration('0001_relations.sql', '''
CREATE TABLE parents (id INTEGER PRIMARY KEY) STRICT;
CREATE TABLE children (
  id INTEGER PRIMARY KEY,
  parent_id INTEGER NOT NULL REFERENCES parents (id)
) STRICT;
''');

      expect(await database.applyMigrations(<SqliteMigration>[migration]), 1);
      await expectLater(
        database.execute(
          BoundSql.raw('INSERT INTO children (id, parent_id) VALUES (1, 99)'),
        ),
        throwsA(
          isA<SqlException>().having(
            (error) => error.code,
            'code',
            SqlErrorCode.constraint,
          ),
        ),
      );
      expect(await _integer(database, 'SELECT count(*) FROM children'), 0);
    });

    test('rejects migrations that change foreign-key enforcement', () async {
      for (final pragma in <String>[
        'PRAGMA foreign_keys = OFF;',
        "PRAGMA main.'foreign_keys' = OFF;",
        'PRAGMA main."foreign_keys" = OFF;',
        'PRAGMA main.`foreign_keys` = OFF;',
        'PRAGMA main.[foreign_keys] = OFF;',
        '; -- empty statement\nPRAGMA main.foreign_keys(OFF);',
      ]) {
        final migration = _migration('0001_disable_foreign_keys.sql', '''
CREATE TABLE parents (id INTEGER PRIMARY KEY) STRICT;
$pragma
CREATE TABLE children (
  id INTEGER PRIMARY KEY,
  parent_id INTEGER NOT NULL REFERENCES parents (id)
) STRICT;
INSERT INTO children (id, parent_id) VALUES (1, 99);
''');

        await expectLater(
          database.applyMigrations(<SqliteMigration>[migration]),
          throwsA(
            isA<SqliteMigrationException>()
                .having(
                  (error) => error.message,
                  'message',
                  contains('cannot change SQLite foreign-key enforcement'),
                )
                .having(
                  (error) => error.migration,
                  'migration',
                  migration.name,
                ),
          ),
          reason: pragma,
        );
        expect(await _integer(database, 'PRAGMA foreign_keys'), 1);
        expect(
          await _integer(
            database,
            "SELECT count(*) FROM sqlite_master WHERE name IN "
            "('parents', 'children')",
          ),
          0,
          reason: pragma,
        );
        expect(
          await _integer(database, 'SELECT count(*) FROM _odroe_migrations'),
          0,
          reason: pragma,
        );
      }
    });

    test('allows unrelated and deferred foreign-key pragmas', () async {
      final migration = _migration('0001_allowed_pragmas.sql', '''
PRAGMA foreign_keys;
PRAGMA defer_foreign_keys = ON;
CREATE TABLE foreign_keys (id INTEGER PRIMARY KEY) STRICT;
PRAGMA table_info(foreign_keys);
PRAGMA foreign_key_list("foreign_keys");
''');

      expect(await database.applyMigrations(<SqliteMigration>[migration]), 1);
      expect(
        await _integer(
          database,
          "SELECT count(*) FROM sqlite_master WHERE name = 'foreign_keys'",
        ),
        1,
      );
    });

    test('rolls back the current file and can retry its correction', () async {
      final first = _migration(
        '0001_create_records.sql',
        'CREATE TABLE records (id INTEGER PRIMARY KEY) STRICT;',
      );
      final broken = _migration('0002_broken.sql', '''
CREATE TABLE partial (id INTEGER PRIMARY KEY) STRICT;
INSERT INTO missing_table VALUES (1);
''');
      await database.applyMigrations(<SqliteMigration>[first]);

      await expectLater(
        database.applyMigrations(<SqliteMigration>[first, broken]),
        throwsA(
          isA<SqliteMigrationException>().having(
            (error) => error.migration,
            'migration',
            broken.name,
          ),
        ),
      );
      expect(
        await _integer(
          database,
          "SELECT count(*) FROM sqlite_master WHERE name = 'partial'",
        ),
        0,
      );
      expect(
        await _integer(database, 'SELECT count(*) FROM _odroe_migrations'),
        1,
      );

      final corrected = _migration(
        broken.name,
        'CREATE TABLE completed (id INTEGER PRIMARY KEY) STRICT;',
      );
      expect(
        await database.applyMigrations(<SqliteMigration>[first, corrected]),
        1,
      );
      expect(
        await _integer(
          database,
          "SELECT count(*) FROM sqlite_master WHERE name = 'completed'",
        ),
        1,
      );
    });

    test('uses SQLite statement boundaries for trigger bodies', () async {
      final migration = _migration('0001_trigger_body.sql', '''
; -- leading empty statement
CREATE TABLE records (id INTEGER PRIMARY KEY) STRICT;
CREATE TABLE audit (record_id INTEGER NOT NULL, event TEXT NOT NULL) STRICT;
CREATE TRIGGER records_audit
AFTER INSERT ON records
BEGIN
  INSERT INTO audit VALUES (new.id, 'first');
  INSERT INTO audit VALUES (new.id, 'second 中文 👋');
END;
INSERT INTO records DEFAULT VALUES;
CREATE INDEX audit_record_id ON audit(record_id);
; -- trailing empty statement
''');

      expect(await database.applyMigrations(<SqliteMigration>[migration]), 1);
      expect(await _integer(database, 'SELECT count(*) FROM audit'), 2);
      expect(
        await _text(
          database,
          "SELECT event FROM audit WHERE event LIKE 'second%'",
        ),
        'second 中文 👋',
      );
      expect(
        await _integer(
          database,
          "SELECT count(*) FROM sqlite_master "
          "WHERE name = 'audit_record_id'",
        ),
        1,
      );
    });

    test('rejects edited, renamed, missing, and backfilled history', () async {
      final first = _migration(
        '0001_create_records.sql',
        'CREATE TABLE records (id INTEGER PRIMARY KEY) STRICT;',
      );
      final third = _migration(
        '0003_add_audit.sql',
        'CREATE TABLE audit (id INTEGER PRIMARY KEY) STRICT;',
      );
      await database.applyMigrations(<SqliteMigration>[first, third]);

      await expectLater(
        database.applyMigrations(<SqliteMigration>[
          _migration(first.name, '${first.sql}\n'),
          third,
        ]),
        _throwsMigration('edited'),
      );
      await expectLater(
        database.applyMigrations(<SqliteMigration>[
          _migration('0001_renamed.sql', first.sql),
          third,
        ]),
        _throwsMigration('renamed'),
      );
      await expectLater(
        database.applyMigrations(<SqliteMigration>[third]),
        _throwsMigration('missing'),
      );

      final second = _migration(
        '0002_backfilled.sql',
        'CREATE TABLE backfilled (id INTEGER PRIMARY KEY) STRICT;',
      );
      await expectLater(
        database.applyMigrations(<SqliteMigration>[first, second, third]),
        _throwsMigration('lower-numbered'),
      );
      expect(
        await _integer(
          database,
          "SELECT count(*) FROM sqlite_master WHERE name = 'backfilled'",
        ),
        0,
      );
    });

    test('prevents a script from escaping its transaction', () async {
      final migration = _migration('0001_escape.sql', '''
CREATE TABLE escaped (id INTEGER PRIMARY KEY) STRICT;
COMMIT;
''');

      await expectLater(
        database.applyMigrations(<SqliteMigration>[migration]),
        throwsA(isA<SqliteMigrationException>()),
      );
      expect(
        await _integer(
          database,
          "SELECT count(*) FROM sqlite_master WHERE name = 'escaped'",
        ),
        0,
      );
      expect(
        await _integer(database, 'SELECT count(*) FROM _odroe_migrations'),
        0,
      );
    });

    test('rejects rollback followed by a replacement transaction', () async {
      final migration = _migration('0001_replace_transaction.sql', '''
CREATE TABLE rolled_back (id INTEGER PRIMARY KEY) STRICT;
ROLLBACK;
BEGIN IMMEDIATE;
CREATE TABLE escaped (id INTEGER PRIMARY KEY) STRICT;
''');

      await expectLater(
        database.applyMigrations(<SqliteMigration>[migration]),
        _throwsMigration('cannot control'),
      );
      for (final table in const <String>['rolled_back', 'escaped']) {
        expect(
          await _integer(
            database,
            "SELECT count(*) FROM sqlite_master WHERE name = '$table'",
          ),
          0,
        );
      }
      expect(
        await _integer(database, 'SELECT count(*) FROM _odroe_migrations'),
        0,
      );
    });

    test('reserves the migration history name in every schema', () async {
      final migration = _migration('0001_temp_shadow.sql', '''
CREATE TEMP TABLE _odroe_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  sql TEXT NOT NULL
) STRICT;
CREATE TABLE records (id INTEGER PRIMARY KEY) STRICT;
''');

      await expectLater(
        database.applyMigrations(<SqliteMigration>[migration]),
        _throwsMigration('cannot modify'),
      );
      expect(
        await _integer(
          database,
          "SELECT count(*) FROM main.sqlite_master WHERE name = 'records'",
        ),
        0,
      );
      expect(
        await _integer(
          database,
          "SELECT count(*) FROM main.sqlite_master "
          "WHERE name = '_odroe_migrations'",
        ),
        0,
      );
    });

    test('allows schema reads but rejects writable schema access', () async {
      final inspecting = _migration('0001_inspect_schema.sql', '''
CREATE TABLE schema_snapshot (object_count INTEGER NOT NULL) STRICT;
INSERT INTO schema_snapshot
SELECT count(*) FROM sqlite_schema;
''');
      expect(await database.applyMigrations(<SqliteMigration>[inspecting]), 1);
      expect(
        await _integer(database, 'SELECT object_count FROM schema_snapshot'),
        greaterThan(0),
      );

      final writable = _migration('0002_writable_schema.sql', '''
PRAGMA 'writable_schema' = ON;
CREATE TABLE leaked (id INTEGER PRIMARY KEY) STRICT;
''');
      await expectLater(
        database.applyMigrations(<SqliteMigration>[inspecting, writable]),
        _throwsMigration('cannot modify'),
      );
      expect(
        await _integer(
          database,
          "SELECT count(*) FROM sqlite_master WHERE name = 'leaked'",
        ),
        0,
      );
    });

    test('rolls back a script that modifies migration history', () async {
      final first = _migration(
        '0001_create_records.sql',
        'CREATE TABLE records (id INTEGER PRIMARY KEY) STRICT;',
      );
      final corrupting = _migration('0002_corrupt_history.sql', '''
UPDATE main._odroe_migrations
SET name = 'temporary_name.sql'
WHERE version = 1;
UPDATE main._odroe_migrations
SET name = '0001_create_records.sql'
WHERE version = 1;
CREATE TABLE leaked (id INTEGER PRIMARY KEY) STRICT;
''');
      await database.applyMigrations(<SqliteMigration>[first]);

      await expectLater(
        database.applyMigrations(<SqliteMigration>[first, corrupting]),
        _throwsMigration('cannot modify'),
      );
      expect(
        await _integer(database, 'SELECT count(*) FROM main._odroe_migrations'),
        1,
      );
      expect(
        await _integer(
          database,
          "SELECT count(*) FROM sqlite_master WHERE name = 'leaked'",
        ),
        0,
      );
    });

    test('rejects ledger replacement and trigger attacks', () async {
      final first = _migration(
        '0001_create_records.sql',
        'CREATE TABLE records (id INTEGER PRIMARY KEY) STRICT;',
      );
      await database.applyMigrations(<SqliteMigration>[first]);

      final replacing = _migration('0002_replace_history.sql', '''
CREATE TABLE replacement AS SELECT * FROM main._odroe_migrations;
DROP TABLE main._odroe_migrations;
ALTER TABLE replacement RENAME TO _odroe_migrations;
CREATE TABLE leaked (id INTEGER PRIMARY KEY) STRICT;
''');
      await expectLater(
        database.applyMigrations(<SqliteMigration>[first, replacing]),
        _throwsMigration('cannot modify'),
      );

      final triggering = _migration('0002_trigger_history.sql', '''
CREATE TRIGGER corrupt_history
AFTER INSERT ON main._odroe_migrations
BEGIN
  UPDATE main._odroe_migrations SET applied_at = 'corrupt';
END;
''');
      await expectLater(
        database.applyMigrations(<SqliteMigration>[first, triggering]),
        _throwsMigration('cannot modify'),
      );
      expect(
        await _text(
          database,
          'SELECT sql FROM main._odroe_migrations WHERE version = 1',
        ),
        first.sql,
      );
      expect(
        await _integer(
          database,
          "SELECT count(*) FROM sqlite_master WHERE name = 'leaked'",
        ),
        0,
      );
    });

    test('rejects a pre-existing trigger on migration history', () async {
      final state = await Directory.systemTemp.createTemp(
        'odroe-migration-schema-attack-',
      );
      final path = p.join(state.path, 'app.sqlite3');
      final setup = sqlite.sqlite3.open(path);
      setup
        ..execute('''
CREATE TABLE _odroe_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  sql TEXT NOT NULL,
  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT;
CREATE TRIGGER corrupt_history
AFTER INSERT ON _odroe_migrations
BEGIN
  UPDATE _odroe_migrations SET applied_at = 'corrupt';
END;
''')
        ..close();
      final attacked = SqliteDatabase.open(path);
      addTearDown(() async {
        await attacked.close();
        if (state.existsSync()) await state.delete(recursive: true);
      });

      await expectLater(
        attacked.applyMigrations(const <SqliteMigration>[]),
        _throwsMigration('schema was modified'),
      );
    });

    test(
      'snapshots a mutable iterable when applyMigrations is called',
      () async {
        final source = <SqliteMigration>[
          _migration(
            '0001_create_records.sql',
            'CREATE TABLE records (id INTEGER PRIMARY KEY) STRICT;',
          ),
        ];

        final applying = database.applyMigrations(source);
        source.clear();

        expect(await applying, 1);
        expect(
          await _integer(
            database,
            "SELECT count(*) FROM sqlite_master WHERE name = 'records'",
          ),
          1,
        );
      },
    );

    test('serializes concurrent calls on the same database', () async {
      final migration = _migration(
        '0001_create_records.sql',
        'CREATE TABLE records (id INTEGER PRIMARY KEY) STRICT;',
      );

      final results = await Future.wait<int>(<Future<int>>[
        database.applyMigrations(<SqliteMigration>[migration]),
        database.applyMigrations(<SqliteMigration>[migration]),
      ]);

      expect(results, <int>[1, 0]);
      expect(
        await _integer(database, 'SELECT count(*) FROM _odroe_migrations'),
        1,
      );
    });

    test('coordinates two connections to the same database', () async {
      final state = await Directory.systemTemp.createTemp(
        'odroe-migration-connections-',
      );
      final first = SqliteDatabase.open(p.join(state.path, 'app.sqlite3'));
      final second = SqliteDatabase.open(p.join(state.path, 'app.sqlite3'));
      addTearDown(() async {
        await first.close();
        await second.close();
        if (state.existsSync()) await state.delete(recursive: true);
      });
      final migration = _migration(
        '0001_create_records.sql',
        'CREATE TABLE records (id INTEGER PRIMARY KEY) STRICT;',
      );

      final results = await Future.wait<int>(<Future<int>>[
        first.applyMigrations(<SqliteMigration>[migration]),
        second.applyMigrations(<SqliteMigration>[migration]),
      ]);

      expect(results, containsAllInOrder(<int>[1, 0]));
      expect(
        await _integer(first, 'SELECT count(*) FROM _odroe_migrations'),
        1,
      );
    });

    test('waits briefly for another process holding the write lock', () async {
      final state = await Directory.systemTemp.createTemp(
        'odroe-migration-lock-',
      );
      final path = p.join(state.path, 'app.sqlite3');
      final setup = sqlite.sqlite3.open(path);
      setup
        ..execute('CREATE TABLE lock_probe (id INTEGER PRIMARY KEY) STRICT;')
        ..close();
      final ready = ReceivePort();
      final exited = ReceivePort();
      final isolate = await Isolate.spawn(_holdSqliteWriteLock, (
        path: path,
        ready: ready.sendPort,
      ), onExit: exited.sendPort);
      addTearDown(() async {
        isolate.kill(priority: Isolate.immediate);
        ready.close();
        exited.close();
        if (state.existsSync()) await state.delete(recursive: true);
      });
      await ready.first.timeout(const Duration(seconds: 5));
      final lockedDatabase = SqliteDatabase.open(path);
      addTearDown(lockedDatabase.close);
      final migration = _migration(
        '0001_create_records.sql',
        'CREATE TABLE records (id INTEGER PRIMARY KEY) STRICT;',
      );

      expect(
        await lockedDatabase.applyMigrations(<SqliteMigration>[migration]),
        1,
      );
      await exited.first.timeout(const Duration(seconds: 5));
    });

    test('revalidates complete history after taking the write lock', () async {
      final state = await Directory.systemTemp.createTemp(
        'odroe-migration-source-race-',
      );
      final path = p.join(state.path, 'app.sqlite3');
      final blocker = sqlite.sqlite3.open(path);
      blocker
        ..execute('''
CREATE TABLE _odroe_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  sql TEXT NOT NULL,
  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT;
CREATE TABLE lock_probe (id INTEGER PRIMARY KEY) STRICT;
''')
        ..execute('BEGIN IMMEDIATE')
        ..execute('INSERT INTO lock_probe DEFAULT VALUES');
      addTearDown(() async {
        blocker.close();
        if (state.existsSync()) await state.delete(recursive: true);
      });
      final results = ReceivePort();
      final first = await Isolate.spawn(_applyIsolatedMigration, (
        path: path,
        name: '0001_first.sql',
        sql: 'CREATE TABLE first (id INTEGER PRIMARY KEY) STRICT;',
        result: results.sendPort,
      ));
      final second = await Isolate.spawn(_applyIsolatedMigration, (
        path: path,
        name: '0002_second.sql',
        sql: 'CREATE TABLE second (id INTEGER PRIMARY KEY) STRICT;',
        result: results.sendPort,
      ));
      addTearDown(() {
        first.kill(priority: Isolate.immediate);
        second.kill(priority: Isolate.immediate);
        results.close();
      });

      final outcomesFuture = results.take(2).toList();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      blocker.execute('COMMIT');
      final outcomes = await outcomesFuture.timeout(
        const Duration(seconds: 10),
      );

      expect(outcomes.whereType<int>(), <int>[1]);
      expect(
        outcomes.whereType<String>().single,
        contains('SqliteMigrationException'),
      );
      final verified = SqliteDatabase.open(path);
      addTearDown(verified.close);
      expect(
        await _integer(verified, 'SELECT count(*) FROM main._odroe_migrations'),
        1,
      );
    });
  });
}

void _holdSqliteWriteLock(({String path, SendPort ready}) message) {
  final database = sqlite.sqlite3.open(message.path);
  try {
    database.execute('BEGIN IMMEDIATE');
    database.execute('INSERT INTO lock_probe DEFAULT VALUES');
    message.ready.send(null);
    sleep(const Duration(milliseconds: 300));
    database.execute('COMMIT');
  } finally {
    database.close();
  }
}

Future<void> _applyIsolatedMigration(
  ({String path, String name, String sql, SendPort result}) message,
) async {
  final database = SqliteDatabase.open(message.path);
  try {
    final applied = await database.applyMigrations(<SqliteMigration>[
      SqliteMigration(name: message.name, sql: message.sql),
    ]);
    message.result.send(applied);
  } on Object catch (error) {
    message.result.send(error.toString());
  } finally {
    await database.close();
  }
}

SqliteMigration _migration(String name, String sql) {
  return SqliteMigration(name: name, sql: sql);
}

Future<int> _integer(SqlDatabase database, String sql) async {
  return (await database.query(
    BoundSql.raw(sql),
    (row) => row.read(0, sqlInt),
  )).single;
}

Future<String> _text(SqlDatabase database, String sql) async {
  return (await database.query(
    BoundSql.raw(sql),
    (row) => row.read(0, sqlText),
  )).single;
}

Matcher _throwsMigration(String message) {
  return throwsA(
    isA<SqliteMigrationException>().having(
      (error) => error.message.toLowerCase(),
      'message',
      contains(message),
    ),
  );
}
