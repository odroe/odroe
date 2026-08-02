import 'dart:async';
import 'dart:typed_data';

import 'package:odroe/database_postgres.dart';
import 'package:test/test.dart';

import 'pool_contract.dart';
import 'support/postgres_cluster.dart';

void main() {
  final unavailableReason = PostgresTestCluster.unavailableReason;

  group('PostgresDatabase', () {
    PostgresTestCluster? cluster;
    late PostgresDatabase database;

    setUpAll(() async {
      cluster = await PostgresTestCluster.start();
    });

    tearDownAll(() => cluster?.close());

    setUp(() async {
      database = await cluster!.openDatabase();
    });

    tearDown(() => database.close());

    test('runs real CRUD and maps native PostgreSQL values', () async {
      await database.execute(
        BoundSql.raw('''
            CREATE TEMP TABLE records (
              id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
              name TEXT NOT NULL,
              active BOOLEAN NOT NULL,
              created_at TIMESTAMPTZ NOT NULL,
              payload BYTEA NOT NULL,
              quantity BIGINT NOT NULL,
              score DOUBLE PRECISION NOT NULL
            )
          '''),
      );
      final createdAt = DateTime.parse(
        '2026-07-30T12:05:06.007008+08:00',
      ).toUtc();
      final payload = Uint8List.fromList(<int>[0, 1, 127, 255]);

      final inserted = await database.execute(
        BoundSql.parts(
          <String>[
            'INSERT INTO records '
                '(name, active, created_at, payload, quantity, score) '
                'VALUES (',
            ', ',
            ', ',
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
            const SqlValue.integer(42),
            SqlValue.real(3.5),
          ],
        ),
      );
      expect(inserted.affectedRows, 1);
      expect(inserted.lastInsertId, isNull);

      final row = (await database.query(
        BoundSql.parts(
          <String>[
            'SELECT id, name, active, created_at, payload, quantity, score '
                'FROM records WHERE name = ',
            '',
          ],
          <SqlValue>[const SqlValue.text('Odroe')],
        ),
        (row) => row,
      )).single;
      expect(
        <String>[
          for (var index = 0; index < row.length; index++) row.nameAt(index),
        ],
        <String>[
          'id',
          'name',
          'active',
          'created_at',
          'payload',
          'quantity',
          'score',
        ],
      );
      expect(row.read(0, sqlInt), 1);
      expect(row.read(1, sqlText), 'Odroe');
      expect(row.read(2, sqlBool), isTrue);
      expect(row.read(3, sqlUtcDateTime), createdAt);
      expect(row.read(4, sqlBlob), orderedEquals(payload));
      expect(row.read(5, sqlInt), 42);
      expect(row.read(6, sqlDouble), 3.5);

      final generatedIds = await database.query(
        BoundSql.parts(
          <String>[
            'INSERT INTO records '
                '(name, active, created_at, payload, quantity, score) '
                'VALUES (',
            ', ',
            ', ',
            ', ',
            ', ',
            ', ',
            ') RETURNING id',
          ],
          <SqlValue>[
            const SqlValue.text('Odroe 2'),
            const SqlValue.boolean(false),
            SqlValue.time(createdAt),
            SqlValue.blob(payload),
            const SqlValue.integer(7),
            SqlValue.real(1.25),
          ],
        ),
        (row) => row.read(0, sqlInt),
      );
      expect(generatedIds, <int>[2]);

      final nulls = await database.query(
        BoundSql.parts(
          <String>['SELECT ', '::text AS value'],
          <SqlValue>[const SqlValue.nullValue()],
        ),
        (row) => row.read(0, nullable(sqlText)),
      );
      expect(nulls, <String?>[null]);

      await database.execute(
        BoundSql.raw('CREATE TEMP TABLE nullable_values (value TEXT)'),
      );
      await database.execute(
        BoundSql.parts(
          <String>['INSERT INTO nullable_values (value) VALUES (', ')'],
          <SqlValue>[const SqlValue.nullValue()],
        ),
      );
      final storedNulls = await database.query(
        BoundSql.raw('SELECT value FROM nullable_values'),
        (row) => row.read(0, nullable(sqlText)),
      );
      expect(storedNulls, <String?>[null]);
    });

    test(
      'runs targeted conflict inserts and preserves the stored row',
      () async {
        await database.execute(
          BoundSql.raw('''
            CREATE TEMP TABLE typed_conflict_posts (
              id BIGINT PRIMARY KEY,
              title TEXT NOT NULL
            )
          '''),
        );
        final posts = _ConflictPosts();
        const queries = SqlQueries(SqlDialect.postgres);

        final first = await queries
            .insertOnConflictDoNothing(
              posts,
              <SqlAssignment>[posts.id.set(42), posts.title.set('Original')],
              target: <SqlTableColumn<Object?>>[posts.id],
            )
            .execute(database);
        expect(first.affectedRows, 1);

        final duplicate = await queries
            .insertOnConflictDoNothing(
              posts,
              <SqlAssignment>[posts.id.set(42), posts.title.set('Replacement')],
              target: <SqlTableColumn<Object?>>[posts.id],
            )
            .execute(database);
        expect(duplicate.affectedRows, 0);

        final returned = await queries
            .insertOnConflictDoNothing(
              posts,
              <SqlAssignment>[
                posts.id.set(42),
                posts.title.set('Returned replacement'),
              ],
              target: <SqlTableColumn<Object?>>[posts.id],
            )
            .returning(posts.projection)
            .all(database);
        expect(returned, isEmpty);

        expect(
          await queries
              .selectTable(posts, where: posts.id.equals(42))
              .one(database),
          (id: 42, title: 'Original'),
        );
      },
    );

    test('binds input without scanning or rewriting SQL fragments', () async {
      await database.execute(
        BoundSql.raw(
          'CREATE TEMP TABLE users '
          '(id BIGINT GENERATED ALWAYS AS IDENTITY, name TEXT NOT NULL)',
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
          <String>[r"SELECT '$9' AS literal, ", r'::bigint AS value /* $2 */'],
          <SqlValue>[const SqlValue.integer(7)],
        ),
        (row) => (row.read(0, sqlText), row.read(1, sqlInt)),
      );
      expect(placeholderText.single, (r'$9', 7));
      expect(await _count(database, 'users'), 1);
    });

    test('preserves duplicate result column names and order', () async {
      final row = (await database.query(
        BoundSql.raw(
          'SELECT 1::bigint AS id, 2::bigint AS id, 3::bigint AS value',
        ),
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

    test('execute rejects row-returning statements', () async {
      await expectLater(
        database.execute(BoundSql.raw('SELECT 1::bigint')),
        _throwsSql(SqlErrorCode.unsupported),
      );
      await database.execute(
        BoundSql.raw(
          'CREATE TEMP TABLE returning_values '
          '(id BIGINT GENERATED ALWAYS AS IDENTITY)',
        ),
      );
      await expectLater(
        database.execute(
          BoundSql.raw(
            'INSERT INTO returning_values DEFAULT VALUES RETURNING id',
          ),
        ),
        _throwsSql(SqlErrorCode.unsupported),
      );
    });

    test('rolls back a failed atomic write', () async {
      await database.execute(
        BoundSql.raw(
          'CREATE TEMP TABLE tags '
          '(id BIGINT GENERATED ALWAYS AS IDENTITY, slug TEXT UNIQUE)',
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

    test(
      'rolls back an interactive transaction when its callback fails',
      () async {
        await database.execute(
          BoundSql.raw(
            'CREATE TEMP TABLE events '
            '(id BIGINT GENERATED ALWAYS AS IDENTITY, name TEXT)',
          ),
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
          'CREATE TEMP TABLE timeline '
          '(id BIGINT GENERATED ALWAYS AS IDENTITY, label TEXT NOT NULL)',
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

    test('rejects unmarked transaction control before sending it', () async {
      await database.execute(
        BoundSql.raw('CREATE TEMP TABLE guarded (value BIGINT)'),
      );

      await expectLater(
        database.transaction<void>((transaction) async {
          await transaction.execute(
            BoundSql.raw(
              'INSERT INTO guarded VALUES (1)',
              kind: SqlStatementKind.write,
            ),
          );
          await expectLater(
            transaction.execute(BoundSql.raw('COMMIT')),
            _throwsSql(SqlErrorCode.unsupported),
          );
          throw StateError('abort after rejected COMMIT');
        }),
        throwsStateError,
      );
      await expectLater(
        database.transaction<void>((transaction) async {
          await transaction.execute(
            BoundSql.raw(
              'INSERT INTO guarded VALUES (2)',
              kind: SqlStatementKind.write,
            ),
          );
          await expectLater(
            transaction.query(BoundSql.raw('ROLLBACK'), (row) => row),
            _throwsSql(SqlErrorCode.unsupported),
          );
          throw StateError('abort after rejected ROLLBACK');
        }),
        throwsStateError,
      );

      expect(await _count(database, 'guarded'), 0);
    });

    test('rejects explicit opposite kinds before execution', () async {
      await database.execute(
        BoundSql.raw('CREATE TEMP TABLE shaped (value BIGINT)'),
      );

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
            dialect: SqlDialect.sqlite,
          ),
          (row) => row,
        ),
        _throwsDialect('PostgreSQL', SqlDialect.sqlite),
      );
      await expectLater(
        database.execute(
          BoundSql.raw(
            _dialectSentinel,
            kind: SqlStatementKind.write,
            dialect: SqlDialect.mysql,
          ),
        ),
        _throwsDialect('PostgreSQL', SqlDialect.mysql),
      );
      await expectLater(
        database.atomicWrite(<BoundSql>[
          BoundSql.raw(
            _dialectSentinel,
            kind: SqlStatementKind.write,
            dialect: SqlDialect.postgres,
          ),
          BoundSql.raw(
            _dialectSentinel,
            kind: SqlStatementKind.write,
            dialect: SqlDialect.sqlite,
          ),
        ]),
        _throwsDialect('PostgreSQL', SqlDialect.sqlite),
      );

      await database.execute(
        BoundSql.raw('CREATE TEMP TABLE dialect_guard (value BIGINT)'),
      );
      await database.transaction<void>((transaction) async {
        await expectLater(
          transaction.query(
            BoundSql.raw(
              _dialectSentinel,
              kind: SqlStatementKind.rowReturning,
              dialect: SqlDialect.sqlite,
            ),
            (row) => row,
          ),
          _throwsDialect('PostgreSQL', SqlDialect.sqlite),
        );
        await expectLater(
          transaction.execute(
            BoundSql.raw(
              _dialectSentinel,
              kind: SqlStatementKind.write,
              dialect: SqlDialect.mysql,
            ),
          ),
          _throwsDialect('PostgreSQL', SqlDialect.mysql),
        );
        await transaction.execute(
          BoundSql.raw(
            'INSERT INTO dialect_guard VALUES (1)',
            kind: SqlStatementKind.write,
            dialect: SqlDialect.postgres,
          ),
        );
      });

      expect(await _count(database, 'dialect_guard'), 1);
    });

    test(
      'invalidates escaped executors and rejects nested transactions',
      () async {
        await database.execute(
          BoundSql.raw('CREATE TEMP TABLE values_table (value BIGINT)'),
        );
        late SqlExecutor escaped;

        await database.transaction<void>((transaction) async {
          escaped = transaction;
          await expectLater(
            database.execute(
              BoundSql.raw('INSERT INTO values_table VALUES (1)'),
            ),
            _throwsSql(SqlErrorCode.unsupported),
          );
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

    test('opens from a URL', () async {
      final fromUrl = await PostgresDatabase.openUrl(cluster!.connectionUrl);
      try {
        final value = await fromUrl.query(
          BoundSql.raw('SELECT 7::bigint'),
          (row) => row.read(0, sqlInt),
        );
        expect(value, <int>[7]);
      } finally {
        await fromUrl.close();
      }
    });

    definePostgresPoolContract(() => cluster!, () => database);

    test('honors explicit ownership for injected connections', () async {
      final borrowed = await cluster!.openConnection();
      final borrowedDatabase = PostgresDatabase.fromConnection(borrowed);
      expect(borrowedDatabase.ownsConnection, isFalse);
      expect(borrowedDatabase.ownsPool, isFalse);
      await borrowedDatabase.close();
      expect(borrowed.isOpen, isTrue);
      await borrowed.execute('SELECT 1');
      await borrowed.close();

      final owned = await cluster!.openConnection();
      final ownedDatabase = PostgresDatabase.fromConnection(
        owned,
        ownsConnection: true,
      );
      expect(ownedDatabase.ownsConnection, isTrue);
      expect(ownedDatabase.ownsPool, isFalse);
      await ownedDatabase.close();
      expect(owned.isOpen, isFalse);
    });

    test('close is idempotent and later operations report closed', () async {
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
        database.execute(BoundSql.raw('CREATE TEMP TABLE no_op (id BIGINT)')),
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

    test('classifies failures without exposing bound values', () async {
      await database.execute(
        BoundSql.raw('''
            CREATE TEMP TABLE accounts (
              id BIGINT GENERATED ALWAYS AS IDENTITY,
              email TEXT NOT NULL UNIQUE
            )
          '''),
      );
      const privateValue = 'private-postgres@example.com';
      await database.execute(_insertAccount(privateValue));

      Object? constraintError;
      try {
        await database.execute(_insertAccount(privateValue));
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
              'accounts_email_key',
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains(privateValue)),
            )
            .having((error) => error.cause, 'cause', isNotNull)
            .having(
              (error) => error.cause.toString(),
              'cause',
              isNot(contains(privateValue)),
            ),
      );

      const invalidValue = 'private-invalid-integer';
      Object? valueError;
      try {
        await database.query(
          BoundSql.parts(
            <String>['SELECT ', '::bigint'],
            <SqlValue>[const SqlValue.text(invalidValue)],
          ),
          (row) => row,
        );
      } on Object catch (error) {
        valueError = error;
      }
      expect(
        valueError,
        isA<SqlException>()
            .having((error) => error.code, 'code', SqlErrorCode.invalidValue)
            .having(
              (error) => error.message,
              'message',
              isNot(contains(invalidValue)),
            )
            .having(
              (error) => error.cause.toString(),
              'cause',
              isNot(contains(invalidValue)),
            ),
      );

      await expectLater(
        database.query(BoundSql.raw('SELEC 1'), (row) => row),
        _throwsSql(SqlErrorCode.driver),
      );
    });
  }, skip: unavailableReason ?? false);
}

typedef _ConflictPost = ({int id, String title});

final class _ConflictPosts extends SqlTable<_ConflictPost> {
  _ConflictPosts() : super('typed_conflict_posts');

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<String> title = column<String>('title', sqlText);

  @override
  late final SqlProjection<_ConflictPost> projection =
      SqlProjection<_ConflictPost>(<SqlSelection<Object?>>[id, title], (row) {
        return (id: id.read(row, 0), title: title.read(row, 1));
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

BoundSql _insertAccount(String email) {
  return BoundSql.parts(
    <String>['INSERT INTO accounts (email) VALUES (', ')'],
    <SqlValue>[SqlValue.text(email)],
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
