import 'dart:async';
import 'dart:io';

import 'package:mysql_dart/mysql_client.dart' as mysql;

import '../database/codec.dart';
import '../database/database.dart';
import '../database/error.dart';
import '../database/result.dart';
import '../database/row.dart';
import '../database/statement.dart';
import 'binding.dart';
import 'error.dart';
import 'value.dart';

/// A Preview MySQL/MariaDB database backed by one serialized connection.
final class MysqlDatabase implements TransactionalSqlDatabase {
  /// Opens and owns one MySQL or MariaDB connection.
  ///
  /// TLS is enabled by default and always rejects an invalid certificate.
  /// Disable it only for an explicitly trusted transport, such as a local
  /// development socket or tunnel.
  static Future<MysqlDatabase> open({
    required String host,
    int port = 3306,
    required String database,
    required String username,
    required String password,
    bool useTls = true,
    SecurityContext? tlsContext,
    bool allowPublicKeyRetrieval = false,
    Duration connectTimeout = const Duration(seconds: 10),
    String collation = 'utf8mb4_general_ci',
    int preparedStatementCacheSize = 32,
  }) async {
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Must be between 1 and 65535.');
    }
    if (connectTimeout.inMilliseconds < 1) {
      throw ArgumentError.value(
        connectTimeout,
        'connectTimeout',
        'Must be at least one millisecond.',
      );
    }
    if (!_collationPattern.hasMatch(collation)) {
      throw ArgumentError.value(
        collation,
        'collation',
        'Must be one MySQL collation identifier.',
      );
    }
    if (preparedStatementCacheSize < 1) {
      throw ArgumentError.value(
        preparedStatementCacheSize,
        'preparedStatementCacheSize',
        'Must be greater than zero.',
      );
    }

    final pending = mysql.MySQLConnection.createConnection(
      host: host,
      port: port,
      userName: username,
      password: password,
      secure: useTls,
      databaseName: database,
      collation: collation,
      securityContext: tlsContext,
      onBadCertificate: (_) => false,
      allowPublicKeyRetrieval: allowPublicKeyRetrieval,
      autoPreparedStatementCacheCapacity: preparedStatementCacheSize,
    );

    late final mysql.MySQLConnection connection;
    try {
      connection = await runMysql(
        () => pending.timeout(connectTimeout),
        operation: 'connect',
        connected: false,
      );
    } on Object {
      _discardLateConnection(pending);
      rethrow;
    }

    try {
      await runMysql(
        () => connection.connect(timeoutMs: connectTimeout.inMilliseconds),
        operation: 'connect',
        connected: connection.connected,
      );
      await runMysql(
        () => connection.execute("SET time_zone = '+00:00'"),
        operation: 'connect',
        connected: connection.connected,
      );
    } on Object {
      await _discardConnection(connection);
      rethrow;
    }

    return MysqlDatabase._(connection);
  }

  MysqlDatabase._(this._connection);

  static final Object _transactionZoneKey = Object();

  final mysql.MySQLConnection _connection;
  final _SerialExecutor _serial = _SerialExecutor();

  bool _closing = false;
  Future<void>? _closeFuture;

  @override
  Future<List<T>> query<T>(BoundSql statement, T Function(SqlRow row) decode) {
    return _schedule(() {
      _requireTopLevelQuery(statement);
      return _query(statement, decode);
    });
  }

  @override
  Future<SqlWriteResult> execute(BoundSql statement) {
    return _schedule(() {
      _requireTopLevelExecute(statement);
      return _execute(statement);
    });
  }

  @override
  Future<List<SqlWriteResult>> atomicWrite(List<BoundSql> statements) {
    final batch = List<BoundSql>.unmodifiable(statements);
    return _schedule(() => _atomicWrite(batch));
  }

  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor transaction) action) {
    if (_insideTransaction) {
      return Future<T>.error(
        const SqlException(
          SqlErrorCode.unsupported,
          'Nested MySQL transactions are not supported.',
        ),
      );
    }
    return _schedule(() => _transaction(action));
  }

  @override
  Future<void> close() {
    if (_insideTransaction) {
      return Future<void>.error(
        const SqlException(
          SqlErrorCode.unsupported,
          'The parent database cannot be closed inside its transaction.',
        ),
      );
    }
    final existing = _closeFuture;
    if (existing != null) return existing;

    _closing = true;
    return _closeFuture = _serial.run(() async {
      if (!_connection.connected) return;
      await runMysql(_connection.close, operation: 'close', connected: true);
    });
  }

  bool get _insideTransaction => _transactionOwners.contains(this);

  Set<MysqlDatabase> get _transactionOwners =>
      Zone.current[_transactionZoneKey] as Set<MysqlDatabase>? ??
      const <MysqlDatabase>{};

  Future<T> _schedule<T>(FutureOr<T> Function() operation) {
    if (_closing) return Future<T>.error(_closed());
    if (_insideTransaction) {
      return Future<T>.error(
        const SqlException(
          SqlErrorCode.unsupported,
          'Use the callback executor inside a MySQL transaction.',
        ),
      );
    }
    return _serial.run(operation);
  }

  Future<List<T>> _query<T>(
    BoundSql statement,
    T Function(SqlRow row) decode,
  ) async {
    final response = await _send(statement, operation: 'query');
    final result = response.result;
    if (result.numOfColumns == 0) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'MySQL query requires a row-returning statement. The unknown '
        'statement may already have run.',
      );
    }
    if (result.next != null) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'MySQL multiple result sets are not supported.',
      );
    }

    final metadata = result.cols.toList(growable: false);
    final columns = <String>[for (final column in metadata) column.name];
    return <T>[
      for (final row in result.rows)
        decode(
          SqlRow(columns, <SqlValue>[
            for (var index = 0; index < columns.length; index++)
              readMysqlValue(
                metadata[index],
                row.colAt(index),
                binary: response.binary,
              ),
          ]),
        ),
    ];
  }

  Future<SqlWriteResult> _execute(BoundSql statement) async {
    final response = await _send(statement, operation: 'execute');
    final result = response.result;
    if (result.numOfColumns != 0) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'MySQL execute requires a non-row-returning statement. The unknown '
        'statement may already have run.',
      );
    }
    if (result.next != null) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'MySQL multiple result sets are not supported.',
      );
    }
    return mysqlWriteResult(result.affectedRows, result.lastInsertID);
  }

  Future<List<SqlWriteResult>> _atomicWrite(List<BoundSql> statements) async {
    _requireAtomicWrites(statements);
    if (statements.isEmpty) return const <SqlWriteResult>[];

    await _control('START TRANSACTION');
    try {
      final results = <SqlWriteResult>[];
      for (final statement in statements) {
        results.add(await _execute(statement));
      }
      await _control('COMMIT');
      return results;
    } on Object catch (error, stackTrace) {
      await _rollbackAfterFailure();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<T> _transaction<T>(
    Future<T> Function(SqlExecutor transaction) action,
  ) async {
    await _control('START TRANSACTION');
    final transaction = _TransactionExecutor(this);
    try {
      final value = await runZoned(
        () => action(transaction),
        zoneValues: <Object?, Object?>{
          _transactionZoneKey: <MysqlDatabase>{..._transactionOwners, this},
        },
      );
      await transaction._seal();
      await _control('COMMIT');
      return value;
    } on Object catch (error, stackTrace) {
      await transaction._seal();
      await _rollbackAfterFailure();
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      transaction._invalidate();
    }
  }

  Future<void> _control(String sql) async {
    if (!_connection.connected) {
      throw _unavailable();
    }
    final result = await runMysql(
      () => _connection.execute(sql),
      operation: 'transaction',
      connected: _connection.connected,
    );
    if (result.numOfColumns != 0 || result.next != null) {
      throw const SqlException(
        SqlErrorCode.driver,
        'MySQL returned an invalid transaction response.',
      );
    }
  }

  Future<void> _rollbackAfterFailure() async {
    try {
      if (_connection.connected) await _control('ROLLBACK');
    } on Object {
      // Preserve the operation that caused the rollback.
    }
  }

  Future<({mysql.IResultSet result, bool binary})> _send(
    BoundSql statement, {
    required String operation,
  }) async {
    if (!_connection.connected) throw _unavailable();
    final bound = bindMysql(statement);
    if (bound.parameters.isNotEmpty) {
      final result = await runMysql(
        () => _connection.execute(bound.sql, bound.parameters),
        operation: operation,
        connected: _connection.connected,
      );
      return (result: result, binary: true);
    }

    // mysql_dart enables CLIENT_MULTI_STATEMENTS for text queries. Rejecting
    // every semicolon on this path is deliberately strict: it prevents a
    // compound statement before I/O without parsing dialect-specific SQL.
    if (bound.sql.contains(';')) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'MySQL statements without bound values cannot contain semicolons.',
      );
    }

    final result = await runMysql(
      () => _connection.execute(bound.sql),
      operation: operation,
      connected: _connection.connected,
    );
    return (result: result, binary: false);
  }
}

final class _TransactionExecutor implements SqlExecutor {
  _TransactionExecutor(this._owner);

  final MysqlDatabase _owner;
  final _SerialExecutor _serial = _SerialExecutor();
  bool _active = true;

  @override
  Future<List<T>> query<T>(BoundSql statement, T Function(SqlRow row) decode) {
    return _schedule(() {
      _requireTransactionQuery(statement);
      return _owner._query(statement, decode);
    });
  }

  @override
  Future<SqlWriteResult> execute(BoundSql statement) {
    return _schedule(() {
      _requireTransactionExecute(statement);
      return _owner._execute(statement);
    });
  }

  Future<T> _schedule<T>(FutureOr<T> Function() operation) {
    if (!_active) return Future<T>.error(_closed());
    return _serial.run(operation);
  }

  Future<void> _seal() {
    _active = false;
    return _serial.idle;
  }

  void _invalidate() {
    _active = false;
  }
}

void _requireTopLevelQuery(BoundSql statement) {
  if (statement.kind == SqlStatementKind.write) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'MySQL query cannot execute a statement declared as write.',
    );
  }
}

void _requireTopLevelExecute(BoundSql statement) {
  if (statement.kind == SqlStatementKind.rowReturning) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'MySQL execute cannot execute a statement declared as rowReturning.',
    );
  }
}

void _requireAtomicWrites(List<BoundSql> statements) {
  for (final statement in statements) {
    if (statement.kind != SqlStatementKind.write) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'MySQL atomicWrite requires kind: SqlStatementKind.write.',
      );
    }
  }
}

void _requireTransactionQuery(BoundSql statement) {
  if (statement.kind != SqlStatementKind.rowReturning) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'MySQL transaction query requires kind: '
      'SqlStatementKind.rowReturning.',
    );
  }
}

void _requireTransactionExecute(BoundSql statement) {
  if (statement.kind != SqlStatementKind.write) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'MySQL transaction execute requires kind: SqlStatementKind.write.',
    );
  }
}

final class _SerialExecutor {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(FutureOr<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<void> get idle => run<void>(() {});
}

void _discardLateConnection(Future<mysql.MySQLConnection> pending) {
  unawaited(
    pending.then<void>(
      (connection) => connection.getSocket().destroy(),
      onError: (Object _, StackTrace _) {},
    ),
  );
}

Future<void> _discardConnection(mysql.MySQLConnection connection) async {
  try {
    if (connection.connected) {
      await connection.close();
    } else {
      connection.getSocket().destroy();
    }
  } on Object {
    connection.getSocket().destroy();
  }
}

SqlException _closed() =>
    const SqlException(SqlErrorCode.closed, 'The MySQL database is closed.');

SqlException _unavailable() =>
    const SqlException(SqlErrorCode.unavailable, 'MySQL is unavailable.');

final RegExp _collationPattern = RegExp(r'^[A-Za-z0-9_]+$');
