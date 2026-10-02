import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:postgres/postgres.dart' as pg;

import '../database/codec.dart';
import '../database/database.dart';
import '../database/dialect.dart';
import '../database/error.dart';
import '../database/result.dart';
import '../database/row.dart';
import '../database/statement.dart';

/// A PostgreSQL database backed by one connection or a lazy connection pool.
final class PostgresDatabase implements TransactionalSqlDatabase {
  /// Opens and owns one PostgreSQL connection.
  static Future<PostgresDatabase> open({
    required String host,
    int port = 5432,
    required String database,
    String? username,
    String? password,
    pg.ConnectionSettings settings = const pg.ConnectionSettings(),
  }) async {
    final connection = await _runPostgres(
      () => pg.Connection.open(
        pg.Endpoint(
          host: host,
          port: port,
          database: database,
          username: username,
          password: password,
        ),
        settings: settings,
      ),
      operation: 'connect',
    );
    return PostgresDatabase._connection(connection, ownsConnection: true);
  }

  /// Opens and owns one PostgreSQL connection from [connectionString].
  static Future<PostgresDatabase> openUrl(String connectionString) async {
    final connection = await _runPostgres(
      () => pg.Connection.openFromUrl(connectionString),
      operation: 'connect',
    );
    return PostgresDatabase._connection(connection, ownsConnection: true);
  }

  /// Wraps an existing [connection].
  ///
  /// The connection remains caller-owned unless [ownsConnection] is true.
  factory PostgresDatabase.fromConnection(
    pg.Connection connection, {
    bool ownsConnection = false,
  }) {
    return PostgresDatabase._connection(
      connection,
      ownsConnection: ownsConnection,
    );
  }

  /// Creates and owns a lazy PostgreSQL connection pool.
  ///
  /// The default [settings] cap the pool at four connections. When supplying
  /// custom settings, set `maxConnectionCount` explicitly.
  static PostgresDatabase pool({
    required String host,
    int port = 5432,
    required String database,
    String? username,
    String? password,
    pg.PoolSettings settings = const pg.PoolSettings(maxConnectionCount: 4),
  }) {
    final pool = pg.Pool<void>.withEndpoints(<pg.Endpoint>[
      pg.Endpoint(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      ),
    ], settings: settings);
    return PostgresDatabase._pool(pool, ownsPool: true);
  }

  /// Creates and owns a lazy PostgreSQL pool from [connectionString].
  ///
  /// Use the `max_connection_count` URL parameter to set its connection limit.
  static PostgresDatabase poolUrl(String connectionString) {
    return PostgresDatabase._pool(
      pg.Pool<void>.withUrl(connectionString),
      ownsPool: true,
    );
  }

  /// Wraps an existing [pool].
  ///
  /// The pool remains caller-owned unless [ownsPool] is true.
  static PostgresDatabase fromPool<L>(
    pg.Pool<L> pool, {
    bool ownsPool = false,
  }) {
    return PostgresDatabase._pool(pool, ownsPool: ownsPool);
  }

  PostgresDatabase._connection(this._connection, {required this.ownsConnection})
    : _pool = null,
      ownsPool = false;

  PostgresDatabase._pool(this._pool, {required this.ownsPool})
    : _connection = null,
      ownsConnection = false;

  static final Object _transactionZoneKey = Object();

  final pg.Connection? _connection;
  final pg.Pool<dynamic>? _pool;
  final _SerialExecutor _serial = _SerialExecutor();

  /// Whether [close] also closes the wrapped PostgreSQL connection.
  final bool ownsConnection;

  /// Whether [close] also closes the wrapped PostgreSQL pool.
  final bool ownsPool;

  bool _closing = false;
  Future<void>? _closeFuture;
  int _activePoolOperations = 0;
  Completer<void>? _poolOperationsDrained;

  @override
  Future<List<T>> query<T>(BoundSql statement, T Function(SqlRow row) decode) {
    return _schedule(() async {
      _requireTopLevelQuery(statement);
      final result = await _runSession(
        (session) => _send(session, statement, operation: 'query'),
        operation: 'query',
      );
      return _decodeQuery(result, decode);
    });
  }

  @override
  Future<SqlWriteResult> execute(BoundSql statement) {
    return _schedule(() async {
      _requireTopLevelExecute(statement);
      final result = await _runSession(
        (session) => _send(session, statement, operation: 'execute'),
        operation: 'execute',
      );
      return _decodeExecute(result);
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
          'Nested PostgreSQL transactions are not supported.',
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
    final pool = _pool;
    final closeFuture = pool == null
        ? _serial.run(() async {
            if (ownsConnection) {
              await _runPostgres(_connection!.close, operation: 'close');
            }
          })
        : _closePool(pool);
    _closeFuture = closeFuture;
    return closeFuture;
  }

  bool get _insideTransaction => _transactionOwners.contains(this);

  Set<PostgresDatabase> get _transactionOwners =>
      Zone.current[_transactionZoneKey] as Set<PostgresDatabase>? ??
      const <PostgresDatabase>{};

  Future<T> _schedule<T>(FutureOr<T> Function() operation) {
    if (_closing) return Future<T>.error(_closed());
    if (_insideTransaction) {
      return Future<T>.error(
        const SqlException(
          SqlErrorCode.unsupported,
          'Use the callback executor inside a PostgreSQL transaction.',
        ),
      );
    }
    if (_pool == null) return _serial.run(operation);

    _activePoolOperations++;
    final result = Completer<T>();
    Future<T>.sync(operation).then(
      (value) {
        result.complete(value);
        _completePoolOperation();
      },
      onError: (Object error, StackTrace stackTrace) {
        result.completeError(error, stackTrace);
        _completePoolOperation();
      },
    );
    return result.future;
  }

  Future<T> _runSession<T>(
    Future<T> Function(pg.Session session) action, {
    required String operation,
  }) {
    final pool = _pool;
    if (pool == null) return action(_connection!);
    return _runPool(pool, () => pool.run(action), operation: operation);
  }

  Future<T> _runTransaction<T>(
    Future<T> Function(pg.TxSession transaction) action,
  ) {
    final pool = _pool;
    if (pool == null) return _connection!.runTx(action);
    return _runPool(pool, () => pool.runTx(action), operation: 'transaction');
  }

  Future<T> _runPool<T>(
    pg.Pool<dynamic> pool,
    Future<T> Function() action, {
    required String operation,
  }) {
    if (!pool.isOpen) return Future<T>.error(_closed());
    return _runPostgres(
      action,
      operation: operation,
      isClosed: () => !pool.isOpen,
    );
  }

  Future<void> _closePool(pg.Pool<dynamic> pool) async {
    if (_activePoolOperations != 0) {
      await (_poolOperationsDrained ??= Completer<void>()).future;
    }
    if (ownsPool) {
      await _runPostgres(() => pool.close(), operation: 'close');
    }
  }

  void _completePoolOperation() {
    _activePoolOperations--;
    if (_activePoolOperations == 0) {
      _poolOperationsDrained?.complete();
    }
  }

  List<T> _decodeQuery<T>(pg.Result result, T Function(SqlRow row) decode) {
    if (result.schema.columns.isEmpty) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'PostgreSQL query requires a row-returning statement. The unknown '
        'statement may already have run.',
      );
    }

    final columns = <String>[
      for (final (index, column) in result.schema.columns.indexed)
        column.columnName ?? '[$index]',
    ];
    return <T>[
      for (final row in result)
        decode(
          SqlRow(columns, <SqlValue>[
            for (var index = 0; index < columns.length; index++)
              _readValue(row, index),
          ]),
        ),
    ];
  }

  Future<SqlWriteResult> _execute(
    pg.Session session,
    BoundSql statement,
  ) async {
    final result = await _send(session, statement, operation: 'execute');
    return _decodeExecute(result);
  }

  SqlWriteResult _decodeExecute(pg.Result result) {
    if (result.schema.columns.isNotEmpty) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'PostgreSQL execute requires a non-row-returning statement. The '
        'unknown statement may already have run.',
      );
    }
    return SqlWriteResult(
      affectedRows: result.affectedRows,
      lastInsertId: null,
    );
  }

  Future<List<SqlWriteResult>> _atomicWrite(List<BoundSql> statements) async {
    _requireAtomicWrites(statements);
    if (statements.isEmpty) return const <SqlWriteResult>[];

    return _runPostgres(
      () => _runTransaction((transaction) async {
        final results = <SqlWriteResult>[];
        for (final statement in statements) {
          results.add(await _execute(transaction, statement));
        }
        return results;
      }),
      operation: 'transaction',
    );
  }

  Future<T> _transaction<T>(
    Future<T> Function(SqlExecutor transaction) action,
  ) async {
    try {
      return await _runPostgres(
        () => _runTransaction((session) async {
          final transaction = _TransactionExecutor(this, session);
          try {
            final result = await runZoned(
              () => action(transaction),
              zoneValues: <Object?, Object?>{
                _transactionZoneKey: <PostgresDatabase>{
                  ..._transactionOwners,
                  this,
                },
              },
            );
            await transaction._seal();
            return result;
          } on Object catch (error, stackTrace) {
            await transaction._seal();
            throw _TransactionCallbackFailure(error, stackTrace);
          } finally {
            transaction._invalidate();
          }
        }),
        operation: 'transaction',
      );
    } on _TransactionCallbackFailure catch (failure) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }
}

final class _TransactionExecutor implements SqlExecutor {
  _TransactionExecutor(this._owner, this._session);

  final PostgresDatabase _owner;
  final pg.TxSession _session;
  final _SerialExecutor _serial = _SerialExecutor();
  bool _active = true;

  @override
  Future<List<T>> query<T>(BoundSql statement, T Function(SqlRow row) decode) {
    return _schedule(() async {
      _requireTransactionQuery(statement);
      final result = await _send(_session, statement, operation: 'query');
      return _owner._decodeQuery(result, decode);
    });
  }

  @override
  Future<SqlWriteResult> execute(BoundSql statement) {
    return _schedule(() {
      _requireTransactionExecute(statement);
      return _owner._execute(_session, statement);
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
  requireSqlDialect(statement.dialect, SqlDialect.postgres, 'PostgreSQL');
  if (statement.kind == SqlStatementKind.write) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'PostgreSQL query cannot execute a statement declared as write.',
    );
  }
}

void _requireTopLevelExecute(BoundSql statement) {
  requireSqlDialect(statement.dialect, SqlDialect.postgres, 'PostgreSQL');
  if (statement.kind == SqlStatementKind.rowReturning) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'PostgreSQL execute cannot execute a statement declared as '
      'rowReturning.',
    );
  }
}

void _requireAtomicWrites(List<BoundSql> statements) {
  for (final statement in statements) {
    requireSqlDialect(statement.dialect, SqlDialect.postgres, 'PostgreSQL');
    if (statement.kind != SqlStatementKind.write) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'PostgreSQL atomicWrite requires kind: SqlStatementKind.write.',
      );
    }
  }
}

void _requireTransactionQuery(BoundSql statement) {
  requireSqlDialect(statement.dialect, SqlDialect.postgres, 'PostgreSQL');
  if (statement.kind != SqlStatementKind.rowReturning) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'PostgreSQL transaction query requires kind: '
      'SqlStatementKind.rowReturning.',
    );
  }
}

void _requireTransactionExecute(BoundSql statement) {
  requireSqlDialect(statement.dialect, SqlDialect.postgres, 'PostgreSQL');
  if (statement.kind != SqlStatementKind.write) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'PostgreSQL transaction execute requires kind: '
      'SqlStatementKind.write.',
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

final class _TransactionCallbackFailure {
  const _TransactionCallbackFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

Future<pg.Result> _send(
  pg.Session session,
  BoundSql statement, {
  required String operation,
}) {
  if (!session.isOpen) return Future<pg.Result>.error(_closed());
  final bound = _bind(statement);
  return _runPostgres(
    () => session.execute(
      bound.sql,
      parameters: bound.parameters,
      queryMode: pg.QueryMode.extended,
    ),
    operation: operation,
  );
}

({pg.Sql sql, List<pg.TypedValue> parameters}) _bind(BoundSql statement) {
  final sql = StringBuffer(statement.fragments.first);
  final parameters = <pg.TypedValue>[];
  for (var index = 0; index < statement.values.length; index++) {
    sql
      ..write(r'$')
      ..write(index + 1)
      ..write(statement.fragments[index + 1]);
    parameters.add(_writeValue(statement.values[index]));
  }
  return (sql: pg.Sql(sql.toString()), parameters: parameters);
}

pg.TypedValue _writeValue(SqlValue value) {
  return switch (value.value) {
    null => pg.TypedValue<Object>(pg.Type.unspecified, null),
    final int value => pg.TypedValue<int>(pg.Type.bigInteger, value),
    final double value => pg.TypedValue<double>(pg.Type.double, value),
    final String value => pg.TypedValue<String>(pg.Type.text, value),
    final bool value => pg.TypedValue<bool>(pg.Type.boolean, value),
    final DateTime value => pg.TypedValue<DateTime>(
      pg.Type.timestampTz,
      value.toUtc(),
    ),
    final Uint8List value => pg.TypedValue<List<int>>(pg.Type.byteArray, value),
    final Object value => throw SqlException(
      SqlErrorCode.invalidValue,
      'PostgreSQL cannot bind ${value.runtimeType}.',
    ),
  };
}

SqlValue _readValue(pg.ResultRow row, int index) {
  if (row.isSqlNull(index)) return const SqlValue.nullValue();

  return switch (row[index]) {
    final int value => SqlValue.integer(value),
    final double value when value.isFinite => SqlValue.real(value),
    double() => throw const SqlException(
      SqlErrorCode.invalidRow,
      'PostgreSQL returned a non-finite number.',
    ),
    final String value => SqlValue.text(value),
    final bool value => SqlValue.boolean(value),
    final DateTime value => SqlValue.time(value),
    final Uint8List value => SqlValue.blob(value),
    final Object? value => throw SqlException(
      SqlErrorCode.invalidRow,
      'PostgreSQL returned unsupported ${value.runtimeType} data.',
    ),
  };
}

Future<T> _runPostgres<T>(
  FutureOr<T> Function() action, {
  required String operation,
  bool Function()? isClosed,
}) async {
  try {
    return await action();
  } on SqlException {
    rethrow;
  } on pg.ServerException catch (error) {
    throw _mapServerException(error);
  } on SocketException catch (error) {
    throw SqlException(
      SqlErrorCode.unavailable,
      'PostgreSQL is unavailable.',
      cause: _PostgresCause(error.runtimeType.toString()),
    );
  } on TimeoutException catch (error) {
    throw SqlException(
      SqlErrorCode.unavailable,
      'PostgreSQL is unavailable.',
      cause: _PostgresCause(error.runtimeType.toString()),
    );
  } on pg.PgException catch (error) {
    final unavailable =
        error.severity == pg.Severity.fatal ||
        error.severity == pg.Severity.panic;
    throw SqlException(
      unavailable ? SqlErrorCode.unavailable : SqlErrorCode.driver,
      unavailable
          ? 'PostgreSQL is unavailable.'
          : 'PostgreSQL $operation failed.',
      cause: _PostgresCause(error.runtimeType.toString()),
    );
  } on ArgumentError catch (error) {
    throw SqlException(
      SqlErrorCode.invalidValue,
      'PostgreSQL rejected a bound value.',
      cause: _PostgresCause(error.runtimeType.toString()),
    );
  } on StateError catch (error) {
    if (isClosed?.call() ?? false) throw _closed();
    throw SqlException(
      SqlErrorCode.driver,
      'PostgreSQL $operation failed.',
      cause: _PostgresCause(error.runtimeType.toString()),
    );
  } on Exception catch (error) {
    throw SqlException(
      SqlErrorCode.driver,
      'PostgreSQL $operation failed.',
      cause: _PostgresCause(error.runtimeType.toString()),
    );
  }
}

SqlException _mapServerException(pg.ServerException error) {
  final sqlState = error.code;
  final code = switch (sqlState) {
    final String value when value.startsWith('23') => SqlErrorCode.constraint,
    final String value when value.startsWith('22') => SqlErrorCode.invalidValue,
    '42P18' || '42804' => SqlErrorCode.invalidValue,
    final String value
        when value.startsWith('08') ||
            value.startsWith('40') ||
            value.startsWith('53') ||
            value == '55P03' ||
            value == '57P01' ||
            value == '57P02' ||
            value == '57P03' ||
            value.startsWith('58') =>
      SqlErrorCode.unavailable,
    _ => SqlErrorCode.driver,
  };
  return SqlException(
    code,
    switch (code) {
      SqlErrorCode.constraint =>
        'A PostgreSQL constraint rejected the operation.',
      SqlErrorCode.invalidValue => 'PostgreSQL rejected a bound value.',
      SqlErrorCode.unavailable => 'PostgreSQL is unavailable.',
      _ => 'PostgreSQL operation failed.',
    },
    constraint: code == SqlErrorCode.constraint ? error.constraintName : null,
    cause: _PostgresCause(error.runtimeType.toString(), sqlState: sqlState),
  );
}

final class _PostgresCause {
  const _PostgresCause(this.driverType, {this.sqlState});

  final String driverType;
  final String? sqlState;

  @override
  String toString() {
    final state = sqlState;
    return state == null ? driverType : '$driverType (SQLSTATE $state)';
  }
}

SqlException _closed() => const SqlException(
  SqlErrorCode.closed,
  'The PostgreSQL database is closed.',
);
