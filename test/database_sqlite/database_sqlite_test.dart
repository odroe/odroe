import 'dart:async';
import 'dart:typed_data';

import 'package:odroe/database_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late SqliteDatabase database;

  setUp(() {
    database = SqliteDatabase.openInMemory();
  });

  tearDown(() => database.close());

  test('runs real CRUD and maps SQLite values', () async {
    await database.execute(
      BoundSql.raw('''
        CREATE TABLE records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          active INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          payload BLOB NOT NULL
        ) STRICT
      '''),
    );
    final createdAt = DateTime.utc(2026, 7, 30, 4, 5, 6, 7, 8);
    final payload = Uint8List.fromList(<int>[0, 1, 127, 255]);

    final inserted = await database.execute(
      BoundSql.parts(
        <String>[
          'INSERT INTO records '
              '(name, active, created_at, payload) VALUES (',
          ', ',
          ', ',
          ', ',
          ')',
        ],
        <SqlValue>[
          const SqlValue.text('Odroe'),
          const SqlValue.boolean(true),
          SqlValue.time(createdAt),
          SqlValue.blob(payload),
        ],
      ),
    );

    expect(inserted.affectedRows, 1);
    expect(inserted.lastInsertId, 1);

    final rows = await database.query(
      BoundSql.raw('SELECT id, name, active, created_at, payload FROM records'),
      (row) => row,
    );
    final row = rows.single;
    expect(
      <String>[
        for (var index = 0; index < row.length; index++) row.nameAt(index),
      ],
      <String>['id', 'name', 'active', 'created_at', 'payload'],
    );
    expect(row.read(0, sqlInt), 1);
    expect(row.read(1, sqlText), 'Odroe');
    expect(row.read(2, sqlBool), isTrue);
    expect(row.read(3, sqlUtcDateTime), createdAt);
    expect(row.read(4, sqlBlob), orderedEquals(payload));

    final updated = await database.execute(
      BoundSql.parts(
        <String>['UPDATE records SET active = ', ' WHERE id = ', ''],
        <SqlValue>[const SqlValue.boolean(false), const SqlValue.integer(1)],
      ),
    );
    expect(updated.affectedRows, 1);
    expect(updated.lastInsertId, isNull);

    final deleted = await database.execute(
      BoundSql.parts(
        <String>['DELETE FROM records WHERE id = ', ''],
        <SqlValue>[const SqlValue.integer(1)],
      ),
    );
    expect(deleted.affectedRows, 1);
    expect(await _count(database, 'records'), 0);
  });

  test('binds input without scanning or rewriting SQL', () async {
    await database.execute(
      BoundSql.raw(
        'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      ),
    );
    const hostile = "Robert'); DROP TABLE users; --";

    await database.execute(
      BoundSql.parts(
        <String>['INSERT INTO users (name) VALUES (', ')'],
        <SqlValue>[SqlValue.text(hostile)],
      ),
    );

    final names = await database.query(
      BoundSql.parts(
        <String>['SELECT name FROM users WHERE name = ', ''],
        <SqlValue>[SqlValue.text(hostile)],
      ),
      (row) => row.read(0, sqlText),
    );
    expect(names, <String>[hostile]);

    final placeholderText = await database.query(
      BoundSql.parts(
        <String>["SELECT '?' AS literal, ", ' AS value -- ?'],
        <SqlValue>[const SqlValue.integer(7)],
      ),
      (row) => (row.read(0, sqlText), row.read(1, sqlInt)),
    );
    expect(placeholderText.single, ('?', 7));
    expect(await _count(database, 'users'), 1);
  });

  test('preserves duplicate result column names and order', () async {
    final row = (await database.query(
      BoundSql.raw('SELECT 1 AS id, 2 AS id, 3 AS value'),
      (row) => row,
    )).single;

    expect(row.length, 3);
    expect(row.nameAt(0), 'id');
    expect(row.nameAt(1), 'id');
    expect(row.nameAt(2), 'value');
    expect(row.read(0, sqlInt), 1);
    expect(row.read(1, sqlInt), 2);
    expect(row.read(2, sqlInt), 3);
  });

  test('rolls back a failed atomic write', () async {
    await database.execute(
      BoundSql.raw(
        'CREATE TABLE tags (id INTEGER PRIMARY KEY, slug TEXT UNIQUE)',
      ),
    );

    await expectLater(
      database.atomicWrite(<BoundSql>[
        _insertTag('odroe'),
        _insertTag('odroe'),
      ]),
      _throwsSql(SqlErrorCode.constraint),
    );

    expect(await _count(database, 'tags'), 0);
  });

  test('reports a reused insert id after a rollback', () async {
    await database.execute(
      BoundSql.raw(
        'CREATE TABLE generated_ids (id INTEGER PRIMARY KEY, value TEXT)',
      ),
    );

    await expectLater(
      database.transaction<void>((transaction) async {
        final inserted = await transaction.execute(
          BoundSql.raw(
            "INSERT INTO generated_ids (value) VALUES ('rolled')",
            kind: SqlStatementKind.write,
          ),
        );
        expect(inserted.lastInsertId, 1);
        throw StateError('rollback');
      }),
      throwsStateError,
    );

    final inserted = await database.execute(
      BoundSql.raw("INSERT INTO generated_ids (value) VALUES ('kept')"),
    );
    expect(inserted.lastInsertId, 1);
  });

  test(
    'rolls back an interactive transaction when its callback fails',
    () async {
      await database.execute(
        BoundSql.raw('CREATE TABLE events (id INTEGER PRIMARY KEY, name TEXT)'),
      );

      await expectLater(
        database.transaction<void>((transaction) async {
          expect(transaction, isNot(isA<SqlDatabase>()));
          await transaction.execute(
            BoundSql.raw(
              "INSERT INTO events (name) VALUES ('temporary')",
              kind: SqlStatementKind.write,
            ),
          );
          final names = await transaction.query(
            BoundSql.raw(
              'SELECT name FROM events',
              kind: SqlStatementKind.rowReturning,
            ),
            (row) => row.read(0, sqlText),
          );
          expect(names, <String>['temporary']);
          throw StateError('abort');
        }),
        throwsStateError,
      );

      expect(await _count(database, 'events'), 0);
    },
  );

  test('keeps external operations outside an active transaction', () async {
    await database.execute(
      BoundSql.raw(
        'CREATE TABLE timeline (id INTEGER PRIMARY KEY, label TEXT NOT NULL)',
      ),
    );
    final entered = Completer<void>();
    final release = Completer<void>();

    final transaction = database.transaction<void>((transaction) async {
      await transaction.execute(_insertTimeline('inside-1'));
      entered.complete();
      await release.future;
      await transaction.execute(_insertTimeline('inside-2'));
    });
    await entered.future;

    var externalCompleted = false;
    final external = database.execute(_insertTimeline('outside')).then((
      result,
    ) {
      externalCompleted = true;
      return result;
    });
    await Future<void>.delayed(Duration.zero);
    expect(externalCompleted, isFalse);

    release.complete();
    await transaction;
    await external;

    final labels = await database.query(
      BoundSql.raw('SELECT label FROM timeline ORDER BY id'),
      (row) => row.read(0, sqlText),
    );
    expect(labels, <String>['inside-1', 'inside-2', 'outside']);
  });

  test(
    'invalidates escaped executors and rejects nested transactions',
    () async {
      await database.execute(
        BoundSql.raw('CREATE TABLE values_table (value INTEGER)'),
      );
      late SqlExecutor escaped;

      await database.transaction<void>((transaction) async {
        escaped = transaction;
      });

      await expectLater(
        escaped.execute(BoundSql.raw('INSERT INTO values_table VALUES (1)')),
        _throwsSql(SqlErrorCode.closed),
      );
      await expectLater(
        database.transaction<void>((_) {
          return database.transaction<void>((_) async {});
        }),
        _throwsSql(SqlErrorCode.unsupported),
      );
      expect(await _count(database, 'values_table'), 0);
    },
  );

  test('keeps every enclosing database in the transaction zone', () async {
    final other = SqliteDatabase.openInMemory();
    try {
      await database.execute(
        BoundSql.raw('CREATE TABLE first_values (value INTEGER)'),
      );
      await other.execute(
        BoundSql.raw('CREATE TABLE second_values (value INTEGER)'),
      );

      await database
          .transaction<void>((_) {
            return other.transaction<void>((_) async {
              await expectLater(
                database.execute(
                  BoundSql.raw('INSERT INTO first_values VALUES (1)'),
                ),
                _throwsSql(SqlErrorCode.unsupported),
              );
              await expectLater(
                database.transaction<void>((_) async {}),
                _throwsSql(SqlErrorCode.unsupported),
              );
            });
          })
          .timeout(const Duration(seconds: 2));
    } finally {
      await other.close();
    }
  });

  test(
    'transaction executors cannot commit or roll back their owner',
    () async {
      await database.execute(
        BoundSql.raw('CREATE TABLE guarded (value INTEGER)'),
      );

      await expectLater(
        database.transaction<void>((transaction) async {
          await transaction.execute(
            BoundSql.raw(
              'INSERT INTO guarded VALUES (1)',
              kind: SqlStatementKind.write,
            ),
          );
          await transaction.execute(BoundSql.raw('COMMIT'));
        }),
        _throwsSql(SqlErrorCode.unsupported),
      );
      await expectLater(
        database.transaction<void>((transaction) async {
          await transaction.execute(
            BoundSql.raw(
              'INSERT INTO guarded VALUES (2)',
              kind: SqlStatementKind.write,
            ),
          );
          await transaction.query(BoundSql.raw('ROLLBACK'), (row) => row);
        }),
        _throwsSql(SqlErrorCode.unsupported),
      );

      expect(await _count(database, 'guarded'), 0);
    },
  );

  test(
    'reports current affected rows and rejects multiple statements',
    () async {
      final created = await database.execute(
        BoundSql.raw('CREATE TABLE changes_source (value INTEGER)'),
      );
      expect(created.affectedRows, 0);

      final inserted = await database.execute(
        BoundSql.raw('INSERT INTO changes_source VALUES (1)'),
      );
      expect(inserted.affectedRows, 1);
      await expectLater(
        database.execute(BoundSql.raw('SELECT value FROM changes_source')),
        _throwsSql(SqlErrorCode.unsupported),
      );

      final secondCreate = await database.execute(
        BoundSql.raw('CREATE TABLE changes_target (value INTEGER)'),
      );
      expect(secondCreate.affectedRows, 0);

      await expectLater(
        database.execute(
          BoundSql.raw(
            'CREATE TABLE hidden_one (value INTEGER); '
            'CREATE TABLE hidden_two (value INTEGER)',
          ),
        ),
        _throwsSql(SqlErrorCode.driver),
      );
      final hiddenTables = await database.query(
        BoundSql.raw('''
        SELECT count(*)
        FROM sqlite_master
        WHERE name IN ('hidden_one', 'hidden_two')
      '''),
        (row) => row.read(0, sqlInt),
      );
      expect(hiddenTables.single, 0);
    },
  );

  test('rejects explicit opposite kinds before execution', () async {
    await database.execute(BoundSql.raw('CREATE TABLE shaped (value INTEGER)'));

    expect(await database.atomicWrite(const <BoundSql>[]), isEmpty);
    await expectLater(
      database.query(
        BoundSql.raw(
          'INSERT INTO shaped VALUES (1)',
          kind: SqlStatementKind.write,
        ),
        (row) => row,
      ),
      _throwsSql(SqlErrorCode.unsupported),
    );
    await expectLater(
      database.execute(
        BoundSql.raw(
          'SELECT value FROM shaped',
          kind: SqlStatementKind.rowReturning,
        ),
      ),
      _throwsSql(SqlErrorCode.unsupported),
    );
    await expectLater(
      database.atomicWrite(<BoundSql>[
        BoundSql.raw('INSERT INTO shaped VALUES (2)'),
      ]),
      _throwsSql(SqlErrorCode.unsupported),
    );

    expect(await _count(database, 'shaped'), 0);
  });

  test('rejects mismatched dialects at every executor boundary', () async {
    await expectLater(
      database.query(
        BoundSql.raw(
          _dialectSentinel,
          kind: SqlStatementKind.rowReturning,
          dialect: SqlDialect.postgres,
        ),
        (row) => row,
      ),
      _throwsDialect('SQLite', SqlDialect.postgres),
    );
    await expectLater(
      database.execute(
        BoundSql.raw(
          _dialectSentinel,
          kind: SqlStatementKind.write,
          dialect: SqlDialect.mysql,
        ),
      ),
      _throwsDialect('SQLite', SqlDialect.mysql),
    );
    await expectLater(
      database.atomicWrite(<BoundSql>[
        BoundSql.raw(
          _dialectSentinel,
          kind: SqlStatementKind.write,
          dialect: SqlDialect.sqlite,
        ),
        BoundSql.raw(
          _dialectSentinel,
          kind: SqlStatementKind.write,
          dialect: SqlDialect.postgres,
        ),
      ]),
      _throwsDialect('SQLite', SqlDialect.postgres),
    );

    await database.execute(
      BoundSql.raw('CREATE TABLE dialect_guard (value INTEGER)'),
    );
    await database.transaction<void>((transaction) async {
      await expectLater(
        transaction.query(
          BoundSql.raw(
            _dialectSentinel,
            kind: SqlStatementKind.rowReturning,
            dialect: SqlDialect.postgres,
          ),
          (row) => row,
        ),
        _throwsDialect('SQLite', SqlDialect.postgres),
      );
      await expectLater(
        transaction.execute(
          BoundSql.raw(
            _dialectSentinel,
            kind: SqlStatementKind.write,
            dialect: SqlDialect.mysql,
          ),
        ),
        _throwsDialect('SQLite', SqlDialect.mysql),
      );
      await transaction.execute(
        BoundSql.raw(
          'INSERT INTO dialect_guard VALUES (1)',
          kind: SqlStatementKind.write,
          dialect: SqlDialect.sqlite,
        ),
      );
    });

    expect(await _count(database, 'dialect_guard'), 1);
  });

  test('close is idempotent and all later operations report closed', () async {
    final first = database.close();
    final second = database.close();

    expect(identical(first, second), isTrue);
    await Future.wait(<Future<void>>[first, second]);
    await database.close();

    await expectLater(
      database.query(BoundSql.raw('SELECT 1'), (row) => row),
      _throwsSql(SqlErrorCode.closed),
    );
    await expectLater(
      database.execute(BoundSql.raw('CREATE TABLE no_op (id INTEGER)')),
      _throwsSql(SqlErrorCode.closed),
    );
    await expectLater(
      database.atomicWrite(<BoundSql>[]),
      _throwsSql(SqlErrorCode.closed),
    );
    await expectLater(
      database.transaction<void>((_) async {}),
      _throwsSql(SqlErrorCode.closed),
    );
  });

  test('maps constraint and driver failures without exposing values', () async {
    await database.execute(
      BoundSql.raw('''
        CREATE TABLE accounts (
          id INTEGER PRIMARY KEY,
          email TEXT NOT NULL UNIQUE
        )
      '''),
    );
    await database.execute(
      BoundSql.parts(
        <String>['INSERT INTO accounts (email) VALUES (', ')'],
        <SqlValue>[const SqlValue.text('private@example.com')],
      ),
    );

    Object? constraintError;
    try {
      await database.execute(
        BoundSql.parts(
          <String>['INSERT INTO accounts (email) VALUES (', ')'],
          <SqlValue>[const SqlValue.text('private@example.com')],
        ),
      );
    } on Object catch (error) {
      constraintError = error;
    }
    expect(
      constraintError,
      isA<SqlException>()
          .having((error) => error.code, 'code', SqlErrorCode.constraint)
          .having(
            (error) => error.constraint,
            'constraint',
            contains('accounts.email'),
          )
          .having(
            (error) => error.message,
            'message',
            isNot(contains('private@example.com')),
          )
          .having((error) => error.cause, 'cause', isNotNull)
          .having(
            (error) => error.cause.toString(),
            'cause',
            isNot(contains('private@example.com')),
          ),
    );

    await expectLater(
      database.query(BoundSql.raw('SELECT FROM'), (row) => row),
      _throwsSql(SqlErrorCode.driver),
    );
  });
}

BoundSql _insertTag(String slug) {
  return BoundSql.parts(
    <String>['INSERT INTO tags (slug) VALUES (', ')'],
    <SqlValue>[SqlValue.text(slug)],
    kind: SqlStatementKind.write,
  );
}

BoundSql _insertTimeline(String label) {
  return BoundSql.parts(
    <String>['INSERT INTO timeline (label) VALUES (', ')'],
    <SqlValue>[SqlValue.text(label)],
    kind: SqlStatementKind.write,
  );
}

Future<int> _count(SqlExecutor database, String table) async {
  final values = await database.query(
    BoundSql.raw('SELECT count(*) FROM $table'),
    (row) => row.read(0, sqlInt),
  );
  return values.single;
}

Matcher _throwsSql(SqlErrorCode code) {
  return throwsA(
    isA<SqlException>().having((error) => error.code, 'code', code),
  );
}

Matcher _throwsDialect(String database, SqlDialect actual) {
  return throwsA(
    isA<SqlException>()
        .having((error) => error.code, 'code', SqlErrorCode.unsupported)
        .having((error) => error.message, 'message', contains(database))
        .having((error) => error.message, 'message', contains(actual.name))
        .having(
          (error) => error.message,
          'message',
          isNot(contains(_dialectSentinel)),
        ),
  );
}

const _dialectSentinel = 'DIALECT_SENTINEL private-value';
