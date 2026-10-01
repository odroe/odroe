import 'dart:async';

import 'package:odroe/database_postgres.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';

import 'support/postgres_cluster.dart';

void definePostgresPoolContract(
  PostgresTestCluster Function() cluster,
  PostgresDatabase Function() singleConnection,
) {
  test('creates lazy owned pools from fields and a URL', () async {
    var openedConnections = 0;
    final fromFields = PostgresDatabase.pool(
      host: '127.0.0.1',
      port: cluster().port,
      database: 'postgres',
      username: 'postgres',
      settings: pg.PoolSettings(
        maxConnectionCount: 1,
        sslMode: pg.SslMode.disable,
        connectTimeout: Duration(seconds: 1),
        onOpen: (_) async {
          openedConnections++;
        },
      ),
    );
    expect(fromFields.ownsConnection, isFalse);
    expect(fromFields.ownsPool, isTrue);
    expect(openedConnections, 0);
    try {
      expect(
        await fromFields.query(
          BoundSql.raw('SELECT 11::bigint'),
          (row) => row.read(0, sqlInt),
        ),
        <int>[11],
      );
      expect(openedConnections, 1);
    } finally {
      await fromFields.close();
    }

    final fromUrl = PostgresDatabase.poolUrl(
      '${cluster().connectionUrl}&max_connection_count=1',
    );
    expect(fromUrl.ownsConnection, isFalse);
    expect(fromUrl.ownsPool, isTrue);
    try {
      expect(
        await fromUrl.query(
          BoundSql.raw('SELECT 13::bigint'),
          (row) => row.read(0, sqlInt),
        ),
        <int>[13],
      );
    } finally {
      await fromUrl.close();
    }
  });

  test('runs concurrent pool transactions on distinct connections', () async {
    final pooled = PostgresDatabase.pool(
      host: '127.0.0.1',
      port: cluster().port,
      database: 'postgres',
      username: 'postgres',
      settings: const pg.PoolSettings(
        maxConnectionCount: 2,
        sslMode: pg.SslMode.disable,
        connectTimeout: Duration(seconds: 1),
      ),
    );
    addTearDown(pooled.close);
    final firstEntered = Completer<int>();
    final secondEntered = Completer<int>();
    final release = Completer<void>();

    Future<int> holdTransaction(Completer<int> entered) async {
      try {
        return await pooled.transaction<int>((transaction) async {
          final backendId = (await transaction.query(
            BoundSql.raw(
              'SELECT pg_backend_pid()::bigint',
              kind: SqlStatementKind.rowReturning,
            ),
            (row) => row.read(0, sqlInt),
          )).single;
          entered.complete(backendId);
          await release.future;
          final sameBackendId = (await transaction.query(
            BoundSql.raw(
              'SELECT pg_backend_pid()::bigint',
              kind: SqlStatementKind.rowReturning,
            ),
            (row) => row.read(0, sqlInt),
          )).single;
          expect(sameBackendId, backendId);
          return backendId;
        });
      } on Object catch (error, stackTrace) {
        if (!entered.isCompleted) {
          entered.completeError(error, stackTrace);
        }
        rethrow;
      }
    }

    final first = holdTransaction(firstEntered);
    final second = holdTransaction(secondEntered);
    try {
      final enteredBackendIds = await Future.wait(<Future<int>>[
        firstEntered.future,
        secondEntered.future,
      ]).timeout(const Duration(seconds: 5));
      expect(enteredBackendIds.toSet(), hasLength(2));
    } finally {
      release.complete();
    }

    final completedBackendIds = await Future.wait(<Future<int>>[first, second]);
    expect(completedBackendIds.toSet(), hasLength(2));
  });

  test('preserves query decoder errors and their original stack', () async {
    final database = singleConnection();
    var openedConnections = 0;
    final pooled = PostgresDatabase.pool(
      host: '127.0.0.1',
      port: cluster().port,
      database: 'postgres',
      username: 'postgres',
      settings: pg.PoolSettings(
        maxConnectionCount: 1,
        sslMode: pg.SslMode.disable,
        connectTimeout: const Duration(seconds: 1),
        onOpen: (_) async {
          openedConnections++;
        },
      ),
    );
    try {
      final firstBackendId = (await pooled.query(
        BoundSql.raw('SELECT pg_backend_pid()::bigint'),
        (row) => row.read(0, sqlInt),
      )).single;
      expect(openedConnections, 1);

      for (final current in <PostgresDatabase>[database, pooled]) {
        final failure = FormatException(
          'decoder failure for ${identical(current, pooled) ? 'pool' : 'single'}',
        );
        StackTrace? thrownStack;
        Object? caught;
        StackTrace? caughtStack;
        try {
          await current.query<Never>(BoundSql.raw('SELECT 1::bigint'), (_) {
            try {
              throw failure;
            } on Object catch (_, stackTrace) {
              thrownStack = stackTrace;
              rethrow;
            }
          });
        } on Object catch (error, stackTrace) {
          caught = error;
          caughtStack = stackTrace;
        }

        expect(caught, same(failure));
        expect(caughtStack.toString(), thrownStack.toString());
      }

      await expectLater(
        pooled.execute(BoundSql.raw('SELECT 2::bigint')),
        _throwsSql(SqlErrorCode.unsupported),
      );
      final secondBackendId = (await pooled.query(
        BoundSql.raw('SELECT pg_backend_pid()::bigint'),
        (row) => row.read(0, sqlInt),
      )).single;
      expect(secondBackendId, firstBackendId);
      expect(openedConnections, 1);
    } finally {
      await pooled.close();
    }
  });

  test('rolls back a failed atomic write through the pool', () async {
    final pooled = PostgresDatabase.poolUrl(
      '${cluster().connectionUrl}&max_connection_count=2',
    );
    try {
      await pooled.execute(
        BoundSql.raw('''
          CREATE TABLE odroe_pool_atomic_write_tags (
            id BIGINT GENERATED ALWAYS AS IDENTITY,
            slug TEXT NOT NULL UNIQUE
          )
        '''),
      );
      await expectLater(
        pooled.atomicWrite(<BoundSql>[
          BoundSql.raw(
            "INSERT INTO odroe_pool_atomic_write_tags (slug) VALUES ('odroe')",
            kind: SqlStatementKind.write,
          ),
          BoundSql.raw(
            "INSERT INTO odroe_pool_atomic_write_tags (slug) VALUES ('odroe')",
            kind: SqlStatementKind.write,
          ),
        ]),
        _throwsSql(SqlErrorCode.constraint),
      );
      expect(await _count(pooled, 'odroe_pool_atomic_write_tags'), 0);
    } finally {
      try {
        await pooled.execute(
          BoundSql.raw('DROP TABLE IF EXISTS odroe_pool_atomic_write_tags'),
        );
      } finally {
        await pooled.close();
      }
    }
  });

  test('honors explicit ownership for injected generic pools', () async {
    final borrowed = pg.Pool<String>.withUrl(
      '${cluster().connectionUrl}&max_connection_count=1',
    );
    final borrowedDatabase = PostgresDatabase.fromPool(borrowed);
    expect(borrowedDatabase.ownsConnection, isFalse);
    expect(borrowedDatabase.ownsPool, isFalse);
    await borrowedDatabase.close();
    expect(borrowed.isOpen, isTrue);
    await borrowed.execute('SELECT 1');
    await borrowed.close();

    final owned = pg.Pool<int>.withUrl(
      '${cluster().connectionUrl}&max_connection_count=1',
    );
    final ownedDatabase = PostgresDatabase.fromPool(owned, ownsPool: true);
    expect(ownedDatabase.ownsConnection, isFalse);
    expect(ownedDatabase.ownsPool, isTrue);
    await ownedDatabase.close();
    expect(owned.isOpen, isFalse);
  });

  test('maps an externally closed borrowed pool to closed', () async {
    final pool = pg.Pool<String>.withUrl(
      '${cluster().connectionUrl}&max_connection_count=1',
    );
    final pooled = PostgresDatabase.fromPool(pool);
    expect(
      await pooled.query(
        BoundSql.raw('SELECT 23::bigint'),
        (row) => row.read(0, sqlInt),
      ),
      <int>[23],
    );
    await pool.close();
    expect(pool.isOpen, isFalse);

    await expectLater(
      pooled.query(BoundSql.raw('SELECT 1'), (row) => row),
      _throwsSql(SqlErrorCode.closed),
    );
    await expectLater(
      pooled.execute(BoundSql.raw('CREATE TABLE never_created (id BIGINT)')),
      _throwsSql(SqlErrorCode.closed),
    );
    var actionCalled = false;
    await expectLater(
      pooled.transaction<void>((_) async {
        actionCalled = true;
      }),
      _throwsSql(SqlErrorCode.closed),
    );
    expect(actionCalled, isFalse);
    await pooled.close();
  });

  test(
    'pool close drains active and queued operations before closing',
    () async {
      final pool = pg.Pool<void>.withUrl(
        '${cluster().connectionUrl}&max_connection_count=1',
      );
      final pooled = PostgresDatabase.fromPool(pool, ownsPool: true);
      final entered = Completer<void>();
      final release = Completer<void>();
      final operation = pooled.transaction<int>((transaction) async {
        final first = (await transaction.query(
          BoundSql.raw(
            'SELECT 17::bigint',
            kind: SqlStatementKind.rowReturning,
          ),
          (row) => row.read(0, sqlInt),
        )).single;
        entered.complete();
        await release.future;
        final second = (await transaction.query(
          BoundSql.raw(
            'SELECT 19::bigint',
            kind: SqlStatementKind.rowReturning,
          ),
          (row) => row.read(0, sqlInt),
        )).single;
        return first + second;
      });
      Future<List<int>>? queued;
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await operation;
        final queuedOperation = queued;
        if (queuedOperation != null) await queuedOperation;
        await pooled.close();
      });
      await entered.future.timeout(const Duration(seconds: 5));

      final events = <String>[];
      final queuedOperation = pooled
          .query(
            BoundSql.raw('SELECT 29::bigint'),
            (row) => row.read(0, sqlInt),
          )
          .then((value) {
            events.add('queued');
            return value;
          });
      queued = queuedOperation;
      final firstClose = pooled.close();
      final secondClose = pooled.close();
      expect(identical(firstClose, secondClose), isTrue);
      var closeCompleted = false;
      firstClose.then((_) {
        closeCompleted = true;
        events.add('close');
      });
      await Future<void>.delayed(Duration.zero);
      expect(closeCompleted, isFalse);
      await expectLater(
        pooled.query(BoundSql.raw('SELECT 1'), (row) => row),
        _throwsSql(SqlErrorCode.closed),
      );

      release.complete();
      expect(await operation, 36);
      expect(await queuedOperation, <int>[29]);
      await firstClose.timeout(const Duration(seconds: 5));
      expect(closeCompleted, isTrue);
      expect(events, <String>['queued', 'close']);
      expect(pool.isOpen, isFalse);
      await pooled.close();
    },
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
