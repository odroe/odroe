import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:postgres/postgres.dart' as pg;

import '../database/codec.dart';
import '../database/database.dart';
import '../database/error.dart';
import '../database/result.dart';
import '../database/row.dart';
import '../database/statement.dart';

/// A PostgreSQL database backed by one serialized native connection.
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
    return PostgresDatabase._(connection, ownsConnection: true);
  }

  /// Opens and owns one PostgreSQL connection from [connectionString].
  static Future<PostgresDatabase> openUrl(String connectionString) async {
    final connection = await _runPostgres(
      () => pg.Connection.openFromUrl(connectionString),
      operation: 'connect',
    );
    return PostgresDatabase._(connection, ownsConnection: true);
  }

  /// Wraps an existing [connection].
  ///
  /// The connection remains caller-owned unless [ownsConnection] is true.
  factory PostgresDatabase.fromConnection(
    pg.Connection connection, {
    bool ownsConnection = false,
  }) {
    return PostgresDatabase._(connection, ownsConnection: ownsConnection);
  }

  PostgresDatabase._(this._connection, {required this.ownsConnection});

  static final Object _transactionZoneKey = Object();

  final pg.Connection _connection;
  final _SerialExecutor _serial = _SerialExecutor();

  /// Whether [close] also closes the wrapped PostgreSQL connection.
  final bool ownsConnection;

  bool _closing = false;
  Future<void>? _closeFuture;

  @override
  Future<List<T>> query<T>(BoundSql statement, T Function(SqlRow row) decode) {
    return _schedule(() {
      _requireTopLevelQuery(statement);
      return _query(_connection, statement, decode);
    });
  }

  @override
  Future<SqlWriteResult> execute(BoundSql statement) {
    return _schedule(() {
      _requireTopLevelExecute(statement);
      return _execute(_connection, statement);
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
    return _closeFuture = _serial.run(() async {
      if (ownsConnection) {
        await _runPostgres(_connection.close, operation: 'close');
      }
    });
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
    return _serial.run(operation);
  }

  Future<List<T>> _query<T>(
    pg.Session session,
    BoundSql statement,
    T Function(SqlRow row) decode,
  ) async {
    final result = await _send(session, statement, operation: 'query');
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
      () => _connection.runTx((transaction) async {
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
        () => _connection.runTx((session) async {
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
    return _schedule(() {
      _requireTransactionQuery(statement);
      return _owner._query(_session, statement, decode);
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
  if (statement.kind == SqlStatementKind.write) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'PostgreSQL query cannot execute a statement declared as write.',
    );
  }
}

void _requireTopLevelExecute(BoundSql statement) {
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
    if (statement.kind != SqlStatementKind.write) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'PostgreSQL atomicWrite requires kind: SqlStatementKind.write.',
      );
    }
  }
}

void _requireTransactionQuery(BoundSql statement) {
  if (statement.kind != SqlStatementKind.rowReturning) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'PostgreSQL transaction query requires kind: '
      'SqlStatementKind.rowReturning.',
    );
  }
}

void _requireTransactionExecute(BoundSql statement) {
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
