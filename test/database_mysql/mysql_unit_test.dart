import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mysql_dart/exception.dart' as mysql_error;
import 'package:mysql_dart/mysql_client.dart' as mysql;
import 'package:mysql_dart/mysql_protocol.dart' as protocol;
import 'package:odroe/database_mysql.dart';
import 'package:odroe/src/database_mysql/binding.dart';
import 'package:odroe/src/database_mysql/error.dart';
import 'package:odroe/src/database_mysql/value.dart';
import 'package:test/test.dart';

void main() {
  test('validates connection options before opening a socket', () async {
    Future<MysqlDatabase> open({
      int port = 3306,
      String collation = 'utf8mb4_general_ci',
      int cacheSize = 32,
      Duration timeout = const Duration(seconds: 1),
    }) {
      return MysqlDatabase.open(
        host: '127.0.0.1',
        port: port,
        database: 'odroe',
        username: 'odroe',
        password: 'secret',
        collation: collation,
        preparedStatementCacheSize: cacheSize,
        connectTimeout: timeout,
      );
    }

    await expectLater(open(port: 0), throwsArgumentError);
    await expectLater(
      open(collation: 'utf8mb4_general_ci; SELECT 1'),
      throwsArgumentError,
    );
    await expectLater(open(cacheSize: 0), throwsArgumentError);
    await expectLater(
      open(timeout: const Duration(microseconds: 1)),
      throwsArgumentError,
    );

    MysqlDatabase pool({
      int port = 3306,
      int maxConnections = 4,
      int maxPendingOperations = 32,
      Duration queueTimeout = const Duration(seconds: 10),
      String collation = 'utf8mb4_general_ci',
      int cacheSize = 32,
      Duration timeout = const Duration(seconds: 1),
    }) {
      return MysqlDatabase.pool(
        host: '127.0.0.1',
        port: port,
        database: 'odroe',
        username: 'odroe',
        password: 'secret',
        maxConnections: maxConnections,
        maxPendingOperations: maxPendingOperations,
        queueTimeout: queueTimeout,
        collation: collation,
        preparedStatementCacheSize: cacheSize,
        connectTimeout: timeout,
      );
    }

    expect(() => pool(port: 0), throwsArgumentError);
    expect(() => pool(maxConnections: 0), throwsArgumentError);
    expect(() => pool(maxPendingOperations: -1), throwsArgumentError);
    expect(
      () => pool(queueTimeout: const Duration(microseconds: 1)),
      throwsArgumentError,
    );
    expect(
      () => pool(collation: 'utf8mb4_general_ci; SELECT 1'),
      throwsArgumentError,
    );
    expect(() => pool(cacheSize: 0), throwsArgumentError);
    expect(
      () => pool(timeout: const Duration(microseconds: 1)),
      throwsArgumentError,
    );
  });

  test('creates a lazy pool and closes it idempotently without I/O', () async {
    final database = MysqlDatabase.pool(
      host: 'not-resolved.invalid',
      database: 'odroe',
      username: 'odroe',
      password: 'secret',
    );

    final firstClose = database.close();
    final secondClose = database.close();
    expect(identical(firstClose, secondClose), isTrue);
    await firstClose;
    await expectLater(
      database.query(BoundSql.raw('SELECT 1'), (row) => row),
      _throwsSql(SqlErrorCode.closed),
    );
  });

  test('failed pooled opens release capacity and advance waiters', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = <Socket>[];
    final subscription = server.listen(accepted.add);
    addTearDown(() async {
      for (final socket in accepted) {
        socket.destroy();
      }
      await subscription.cancel();
      await server.close();
    });
    final database = MysqlDatabase.pool(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      database: 'odroe',
      username: 'odroe',
      password: 'secret',
      maxConnections: 1,
      useTls: false,
      connectTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(database.close);

    final codes = await Future.wait(<Future<SqlErrorCode>>[
      _readSqlCode(database.query(BoundSql.raw('SELECT 1'), (row) => row)),
      _readSqlCode(database.query(BoundSql.raw('SELECT 2'), (row) => row)),
    ]).timeout(const Duration(seconds: 2));

    expect(codes, <SqlErrorCode>[
      SqlErrorCode.unavailable,
      SqlErrorCode.unavailable,
    ]);
  });

  test('bounds the pending pool queue and times out acquisition', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = <Socket>[];
    final subscription = server.listen(accepted.add);
    addTearDown(() async {
      for (final socket in accepted) {
        socket.destroy();
      }
      await subscription.cancel();
      await server.close();
    });
    final database = MysqlDatabase.pool(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      database: 'odroe',
      username: 'odroe',
      password: 'secret',
      maxConnections: 1,
      maxPendingOperations: 1,
      queueTimeout: const Duration(milliseconds: 20),
      useTls: false,
      connectTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(database.close);

    final opening = _readSqlError(
      database.query(BoundSql.raw('SELECT 1'), (row) => row),
    );
    final waiting = _readSqlError(
      database.query(BoundSql.raw('SELECT 2'), (row) => row),
    );
    final rejected = _readSqlError(
      database.query(BoundSql.raw('SELECT 3'), (row) => row),
    );

    expect((await rejected).message, 'The MySQL pool pending queue is full.');
    expect(
      (await waiting).message,
      'Timed out waiting for a MySQL pool connection.',
    );
    expect((await opening).code, SqlErrorCode.unavailable);
  });

  group('MySQL binding', () {
    test('interleaves fragments directly without scanning SQL', () {
      final timestamp = DateTime.parse('2026-07-30T12:05:06.007008+08:00');
      final bytes = Uint8List.fromList(<int>[0, 127, 255]);
      final binding = bindMysql(
        BoundSql.parts(
          <String>[
            r"SELECT '?' AS literal, ",
            r' AS value /* ? */, ',
            ', ',
            ', ',
            ', ',
            ', ',
            ', ',
            '',
          ],
          <SqlValue>[
            const SqlValue.integer(7),
            SqlValue.real(3.5),
            const SqlValue.text('secret'),
            const SqlValue.boolean(true),
            SqlValue.time(timestamp),
            SqlValue.blob(bytes),
            const SqlValue.nullValue(),
          ],
        ),
      );

      expect(
        binding.sql,
        r"SELECT '?' AS literal, ? AS value /* ? */, ?, ?, ?, ?, ?, ?",
      );
      expect(binding.parameters[0], 7);
      expect(binding.parameters[1], 3.5);
      expect(binding.parameters[2], 'secret');
      expect(binding.parameters[3], isTrue);
      expect(binding.parameters[4], timestamp.toUtc());
      expect(identical(binding.parameters[5], bytes), isTrue);
      expect(binding.parameters[6], isNull);
    });

    test('does not add a placeholder to raw SQL', () {
      final binding = bindMysql(BoundSql.raw('SELECT 1'));

      expect(binding.sql, 'SELECT 1');
      expect(binding.parameters, isEmpty);
    });
  });

  group('MySQL result values', () {
    test('normalizes integers, doubles, text, blobs, and NULL', () {
      expect(
        readMysqlValue(
          _column(protocol.MySQLColumnType.longLongType),
          '-7',
          binary: true,
        ).value,
        -7,
      );
      expect(
        readMysqlValue(
          _column(protocol.MySQLColumnType.doubleType),
          '3.5',
          binary: true,
        ).value,
        3.5,
      );
      expect(
        readMysqlValue(
          _column(protocol.MySQLColumnType.varStringType),
          'text',
          binary: true,
        ).value,
        'text',
      );

      final bytes = Uint8List.fromList(<int>[0, 255]);
      expect(
        identical(
          readMysqlValue(
            _column(protocol.MySQLColumnType.blobType),
            bytes,
            binary: true,
          ).value,
          bytes,
        ),
        isTrue,
      );
      expect(
        readMysqlValue(
          _column(protocol.MySQLColumnType.nullType),
          null,
          binary: true,
        ).isNull,
        isTrue,
      );
    });

    test('normalizes binary and text timestamp fractions correctly', () {
      final column = _column(protocol.MySQLColumnType.dateTimeType);

      expect(
        readMysqlValue(column, '2026-07-30 04:05:06.7008', binary: true).value,
        DateTime.utc(2026, 7, 30, 4, 5, 6, 7, 8),
      );
      expect(
        readMysqlValue(
          column,
          '2026-07-30 04:05:06.007008',
          binary: false,
        ).value,
        DateTime.utc(2026, 7, 30, 4, 5, 6, 7, 8),
      );
      expect(
        readMysqlValue(
          _column(protocol.MySQLColumnType.dateType),
          '2026-07-30',
          binary: false,
        ).value,
        DateTime.utc(2026, 7, 30),
      );
    });

    test('rejects values outside the portable domain', () {
      expect(
        () => readMysqlValue(
          _column(protocol.MySQLColumnType.longLongType),
          '18446744073709551615',
          binary: false,
        ),
        _throwsSql(SqlErrorCode.invalidRow),
      );
      expect(
        () => readMysqlValue(
          _column(protocol.MySQLColumnType.doubleType),
          'Infinity',
          binary: false,
        ),
        _throwsSql(SqlErrorCode.invalidRow),
      );
      expect(
        () => readMysqlValue(
          _column(protocol.MySQLColumnType.dateTimeType),
          '0000-00-00 00:00:00',
          binary: true,
        ),
        _throwsSql(SqlErrorCode.invalidRow),
      );
      expect(
        () => readMysqlValue(
          _column(protocol.MySQLColumnType.timeType),
          '12:00:00',
          binary: true,
        ),
        _throwsSql(SqlErrorCode.invalidRow),
      );
    });

    test('checks affected rows and generated IDs before conversion', () {
      final result = mysqlWriteResult(BigInt.one, BigInt.from(42));
      expect(result.affectedRows, 1);
      expect(result.lastInsertId, 42);
      expect(mysqlWriteResult(BigInt.zero, BigInt.zero).lastInsertId, isNull);

      expect(
        () => mysqlWriteResult(BigInt.from(-1), BigInt.zero),
        _throwsSql(SqlErrorCode.invalidRow),
      );
      expect(
        () => mysqlWriteResult(BigInt.one << 80, BigInt.zero),
        _throwsSql(SqlErrorCode.invalidRow),
      );
      expect(
        () => mysqlWriteResult(BigInt.zero, BigInt.one << 80),
        _throwsSql(SqlErrorCode.invalidRow),
      );
    });
  });

  group('MySQL errors', () {
    test('maps structured server numbers without retaining messages', () {
      const secret = 'bound-value-that-must-not-leak';
      final error = mapMysqlServerError(
        const mysql_error.MySQLServerException(secret, 1062),
      );

      expect(error.code, SqlErrorCode.constraint);
      expect(error.constraint, isNull);
      expect(error.message, isNot(contains(secret)));
      expect(error.cause.toString(), isNot(contains(secret)));
      expect(error.cause.toString(), contains('1062'));
    });

    test('classifies invalid and transient server failures', () {
      expect(
        mapMysqlServerError(
          const mysql_error.MySQLServerException('ignored', 1292),
        ).code,
        SqlErrorCode.invalidValue,
      );
      expect(
        mapMysqlServerError(
          const mysql_error.MySQLServerException('ignored', 1213),
        ).code,
        SqlErrorCode.unavailable,
      );
      expect(
        mapMysqlServerError(
          const mysql_error.MySQLServerException('ignored', 9999),
        ).code,
        SqlErrorCode.driver,
      );
    });

    test('sanitizes client failures and maps lost connections', () async {
      const secret = 'parameter-secret';

      await expectLater(
        runMysql<void>(
          () => throw const mysql_error.MySQLClientException(secret),
          operation: 'query',
        ),
        throwsA(
          isA<SqlException>()
              .having((error) => error.code, 'code', SqlErrorCode.driver)
              .having(
                (error) => error.message,
                'message',
                isNot(contains(secret)),
              )
              .having(
                (error) => error.cause.toString(),
                'cause',
                isNot(contains(secret)),
              ),
        ),
      );

      await expectLater(
        runMysql<void>(
          () => throw const mysql_error.MySQLClientException(secret),
          operation: 'query',
          connected: false,
        ),
        _throwsSql(SqlErrorCode.unavailable),
      );
      await expectLater(
        runMysql<void>(
          () => throw TimeoutException(secret),
          operation: 'connect',
          connected: false,
        ),
        _throwsSql(SqlErrorCode.unavailable),
      );
    });
  });
}

mysql.ResultSetColumn _column(protocol.MySQLColumnType type) {
  return mysql.ResultSetColumn(name: 'value', type: type, length: 0);
}

Matcher _throwsSql(SqlErrorCode code) {
  return throwsA(
    isA<SqlException>().having((error) => error.code, 'code', code),
  );
}

Future<SqlErrorCode> _readSqlCode(Future<Object?> operation) async {
  return (await _readSqlError(operation)).code;
}

Future<SqlException> _readSqlError(Future<Object?> operation) async {
  try {
    await operation;
  } on SqlException catch (error) {
    return error;
  }
  throw StateError('Expected a SqlException.');
}
