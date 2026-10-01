import 'dart:async';
import 'dart:io';

import 'package:odroe/database_mysql.dart';
import 'package:test/test.dart';

typedef MysqlPoolFactory =
    MysqlDatabase Function({
      int? maxConnections,
      int? maxPendingOperations,
      Duration? queueTimeout,
    });

void defineMysqlPoolContract(
  MysqlPoolFactory createPool,
  Future<MysqlDatabase> Function() openControlConnection,
) {
  final suffix = '${pid}_${DateTime.now().microsecondsSinceEpoch}';

  test('runs concurrent transactions on distinct UTC connections', () async {
    final database = createPool(maxConnections: 2);
    addTearDown(database.close);
    final firstEntered = Completer<({int id, String timeZone})>();
    final secondEntered = Completer<({int id, String timeZone})>();
    final release = Completer<void>();

    Future<({int id, String timeZone})> holdTransaction(
      Completer<({int id, String timeZone})> entered,
    ) async {
      try {
        return await database.transaction((transaction) async {
          final session = (await transaction.query(
            BoundSql.raw(
              'SELECT CONNECTION_ID(), @@session.time_zone',
              kind: SqlStatementKind.rowReturning,
            ),
            (row) => (id: row.read(0, sqlInt), timeZone: row.read(1, sqlText)),
          )).single;
          entered.complete(session);
          await release.future;
          final sameConnection = (await transaction.query(
            BoundSql.raw(
              'SELECT CONNECTION_ID()',
              kind: SqlStatementKind.rowReturning,
            ),
            (row) => row.read(0, sqlInt),
          )).single;
          expect(sameConnection, session.id);
          return session;
        });
      } on Object catch (error, stackTrace) {
        if (!entered.isCompleted) entered.completeError(error, stackTrace);
        rethrow;
      }
    }

    final first = holdTransaction(firstEntered);
    final second = holdTransaction(secondEntered);
    try {
      final sessions = await Future.wait(<Future<({int id, String timeZone})>>[
        firstEntered.future,
        secondEntered.future,
      ]).timeout(const Duration(seconds: 5));
      expect(<int>{for (final session in sessions) session.id}, hasLength(2));
      expect(<String>[
        for (final session in sessions) session.timeZone,
      ], everyElement('+00:00'));
    } finally {
      release.complete();
    }

    final sessions = await Future.wait(<Future<({int id, String timeZone})>>[
      first,
      second,
    ]);
    expect(<int>{for (final session in sessions) session.id}, hasLength(2));
  });

  test('preserves transaction callback errors and their stack', () async {
    final database = createPool(maxConnections: 1);
    addTearDown(database.close);
    final failure = StateError('pool callback failure');
    StackTrace? thrownStack;
    Object? caught;
    StackTrace? caughtStack;

    try {
      await database.transaction<void>((_) async {
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
  });

  test(
    'preserves decoder errors without retiring a healthy connection',
    () async {
      final database = createPool(maxConnections: 1);
      addTearDown(database.close);
      final firstConnectionId = (await database.query(
        BoundSql.raw('SELECT CONNECTION_ID()'),
        (row) => row.read(0, sqlInt),
      )).single;
      final failure = FormatException('pooled decoder failure');
      StackTrace? thrownStack;
      Object? caught;
      StackTrace? caughtStack;

      try {
        await database.query<Never>(BoundSql.raw('SELECT 1'), (_) {
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
      final secondConnectionId = (await database.query(
        BoundSql.raw('SELECT CONNECTION_ID()'),
        (row) => row.read(0, sqlInt),
      )).single;
      expect(secondConnectionId, firstConnectionId);
    },
  );

  test('rolls back an atomic write through one pooled connection', () async {
    final database = createPool(maxConnections: 2);
    final table = 'odroe_mysql_pool_atomic_$suffix';
    addTearDown(() async {
      try {
        await database.execute(BoundSql.raw('DROP TABLE IF EXISTS `$table`'));
      } finally {
        await database.close();
      }
    });
    await database.execute(
      BoundSql.raw(
        'CREATE TABLE `$table` ('
        'id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY, '
        'slug VARCHAR(191) NOT NULL UNIQUE)',
      ),
    );

    await expectLater(
      database.atomicWrite(<BoundSql>[
        _insert(table, 'odroe'),
        _insert(table, 'odroe'),
      ]),
      _throwsSql(SqlErrorCode.constraint),
    );
    expect(
      await database.query(
        BoundSql.raw('SELECT COUNT(*) FROM `$table`'),
        (row) => row.read(0, sqlInt),
      ),
      <int>[0],
    );
  });

  test('retires a connection when rollback cannot clean its session', () async {
    final database = createPool(maxConnections: 1);
    final control = await openControlConnection();
    addTearDown(database.close);
    addTearDown(control.close);
    late int killedConnectionId;

    await expectLater(
      database.transaction<void>((transaction) async {
        killedConnectionId = (await transaction.query(
          BoundSql.raw(
            'SELECT CONNECTION_ID()',
            kind: SqlStatementKind.rowReturning,
          ),
          (row) => row.read(0, sqlInt),
        )).single;
        await control.execute(BoundSql.raw('KILL $killedConnectionId'));
        throw StateError('abort after connection loss');
      }),
      throwsStateError,
    );

    final replacementConnectionId = (await database.query(
      BoundSql.raw('SELECT CONNECTION_ID()'),
      (row) => row.read(0, sqlInt),
    )).single;
    expect(replacementConnectionId, isNot(killedConnectionId));
  });

  test('bounds pending work and times out queued operations', () async {
    final database = createPool(
      maxConnections: 1,
      maxPendingOperations: 2,
      queueTimeout: const Duration(milliseconds: 30),
    );
    final entered = Completer<void>();
    final release = Completer<void>();
    final active = database.transaction<void>((_) async {
      entered.complete();
      await release.future;
    });
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      try {
        await active;
      } on Object {
        // Preserve the original test failure.
      }
      await database.close();
    });
    await entered.future.timeout(const Duration(seconds: 5));

    final firstWaiter = _readSqlError(
      database.query(BoundSql.raw('SELECT 31'), (row) => row),
    );
    final secondWaiter = _readSqlError(
      database.query(BoundSql.raw('SELECT 37'), (row) => row),
    );
    final rejected = _readSqlError(
      database.query(BoundSql.raw('SELECT 41'), (row) => row),
    );

    expect((await rejected).message, 'The MySQL pool pending queue is full.');
    for (final waiter in <Future<SqlException>>[firstWaiter, secondWaiter]) {
      expect(
        (await waiter).message,
        'Timed out waiting for a MySQL pool connection.',
      );
    }
    release.complete();
    await active;
    expect(
      await database.query(
        BoundSql.raw('SELECT 43'),
        (row) => row.read(0, sqlInt),
      ),
      <int>[43],
    );
  });

  test('close drains active and queued pool operations', () async {
    final database = createPool(maxConnections: 1);
    final entered = Completer<void>();
    final release = Completer<void>();
    final active = database.transaction<int>((transaction) async {
      final first = (await transaction.query(
        BoundSql.raw('SELECT 17', kind: SqlStatementKind.rowReturning),
        (row) => row.read(0, sqlInt),
      )).single;
      entered.complete();
      await release.future;
      final second = (await transaction.query(
        BoundSql.raw('SELECT 19', kind: SqlStatementKind.rowReturning),
        (row) => row.read(0, sqlInt),
      )).single;
      return first + second;
    });
    Future<List<int>>? queuedOperation;
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      try {
        await active;
      } on Object {
        // Preserve the original test failure.
      }
      final queued = queuedOperation;
      if (queued != null) {
        try {
          await queued;
        } on Object {
          // Preserve the original test failure.
        }
      }
      await database.close();
    });
    await entered.future.timeout(const Duration(seconds: 5));

    var queuedCompleted = false;
    final queued = queuedOperation = database
        .query(BoundSql.raw('SELECT 23'), (row) => row.read(0, sqlInt))
        .then((value) {
          queuedCompleted = true;
          return value;
        });
    final firstClose = database.close();
    final secondClose = database.close();
    expect(identical(firstClose, secondClose), isTrue);
    await expectLater(
      database.query(BoundSql.raw('SELECT 29'), (row) => row),
      _throwsSql(SqlErrorCode.closed),
    );
    await Future<void>.delayed(Duration.zero);
    expect(queuedCompleted, isFalse);

    release.complete();
    expect(await active, 36);
    expect(await queued, <int>[23]);
    await firstClose;
  });
}

BoundSql _insert(String table, String slug) {
  return BoundSql.parts(
    <String>['INSERT INTO `$table` (slug) VALUES (', ')'],
    <SqlValue>[SqlValue.text(slug)],
    kind: SqlStatementKind.write,
  );
}

Matcher _throwsSql(SqlErrorCode code) {
  return throwsA(
    isA<SqlException>().having((error) => error.code, 'code', code),
  );
}

Future<SqlException> _readSqlError(Future<Object?> operation) async {
  try {
    await operation;
  } on SqlException catch (error) {
    return error;
  }
  throw StateError('Expected a SqlException.');
}
