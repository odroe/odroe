import 'dart:async';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../database/codec.dart';
import '../database/database.dart';
import '../database/error.dart';
import '../database/result.dart';
import '../database/row.dart';
import '../database/statement.dart';

/// A native SQLite database with serialized access.
final class SqliteDatabase implements TransactionalSqlDatabase {
  /// Opens the SQLite database at [path].
  factory SqliteDatabase.open(String path) {
    return SqliteDatabase._(
      _runSqlite(() => sqlite.sqlite3.open(path), operation: 'open'),
    );
  }

  /// Opens a private in-memory SQLite database.
  factory SqliteDatabase.openInMemory() {
    return SqliteDatabase._(
      _runSqlite(sqlite.sqlite3.openInMemory, operation: 'open'),
    );
  }

  SqliteDatabase._(this._database) {
    _updates = _database.updatesSync.listen((update) {
      _writeObservation?.add(update.kind);
    });
  }

  static final Object _transactionZoneKey = Object();

  final sqlite.Database _database;
  final _SerialExecutor _serial = _SerialExecutor();
  late final StreamSubscription<sqlite.SqliteUpdate> _updates;
  _WriteObservation? _writeObservation;
  int _totalChanges = 0;
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
          'Nested SQLite transactions are not supported.',
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
      await _updates.cancel();
      _runSqlite(_database.close, operation: 'close');
    });
  }

  bool get _insideTransaction => _transactionOwners.contains(this);

  Set<SqliteDatabase> get _transactionOwners =>
      Zone.current[_transactionZoneKey] as Set<SqliteDatabase>? ??
      const <SqliteDatabase>{};

  Future<T> _schedule<T>(FutureOr<T> Function() operation) {
    if (_closing) return Future<T>.error(_closed());
    if (_insideTransaction) {
      return Future<T>.error(
        const SqlException(
          SqlErrorCode.unsupported,
          'Use the callback executor inside a SQLite transaction.',
        ),
      );
    }
    return _serial.run(operation);
  }

  List<T> _query<T>(BoundSql statement, T Function(SqlRow row) decode) {
    final bound = _bind(statement);
    final prepared = _prepare(bound.sql);
    late final sqlite.ResultSet result;
    try {
      if (prepared.raw.columnCount == 0) {
        throw const SqlException(
          SqlErrorCode.unsupported,
          'SQLite query requires a row-returning statement. An unknown '
          'statement may already have run on drivers that cannot inspect it.',
        );
      }
      try {
        result = _runSqlite(
          () => prepared.select(bound.parameters),
          operation: 'query',
        );
      } on Object {
        if (!prepared.isReadOnly) _synchronizeTotalChanges();
        rethrow;
      }
      if (!prepared.isReadOnly) _refreshTotalChanges();
    } finally {
      prepared.close();
    }
    final columns = result.columnNames;
    return <T>[
      for (final row in result)
        decode(
          SqlRow(columns, <SqlValue>[
            for (var index = 0; index < columns.length; index++)
              _readValue(row.columnAt(index)),
          ]),
        ),
    ];
  }

  SqlWriteResult _execute(
    BoundSql statement, {
    bool requireDirectWrite = false,
  }) {
    final bound = _bind(statement);
    final prepared = _prepare(bound.sql);
    try {
      if (prepared.raw.columnCount != 0) {
        throw const SqlException(
          SqlErrorCode.unsupported,
          'SQLite execute requires a non-row-returning statement. An unknown '
          'statement may already have run on drivers that cannot inspect it.',
        );
      }
      if (requireDirectWrite && prepared.isReadOnly) {
        throw const SqlException(
          SqlErrorCode.unsupported,
          'SQLite transaction executors require a direct write statement.',
        );
      }

      final observation = _WriteObservation();
      _writeObservation = observation;
      var changed = false;
      try {
        try {
          _runSqlite(
            () => prepared.execute(bound.parameters),
            operation: 'execute',
          );
        } on Object {
          if (!prepared.isReadOnly) _synchronizeTotalChanges();
          rethrow;
        }
        changed = !prepared.isReadOnly && _refreshTotalChanges() > 0;
      } finally {
        _writeObservation = null;
      }

      final insertId = _database.lastInsertRowId;
      return SqlWriteResult(
        affectedRows: changed ? _database.updatedRows : 0,
        lastInsertId: observation.isDirectInsert && insertId >= 0
            ? insertId
            : null,
      );
    } finally {
      prepared.close();
    }
  }

  List<SqlWriteResult> _atomicWrite(List<BoundSql> statements) {
    _requireAtomicWrites(statements);
    if (statements.isEmpty) return const <SqlWriteResult>[];
    _control('BEGIN');
    try {
      final results = <SqlWriteResult>[
        for (final statement in statements)
          _execute(statement, requireDirectWrite: true),
      ];
      _control('COMMIT');
      return results;
    } on Object catch (error, stackTrace) {
      _rollback();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<T> _transaction<T>(
    Future<T> Function(SqlExecutor transaction) action,
  ) async {
    _control('BEGIN');
    final transaction = _TransactionExecutor(this);
    try {
      final result = await runZoned(
        () => action(transaction),
        zoneValues: <Object?, Object?>{
          _transactionZoneKey: <SqliteDatabase>{..._transactionOwners, this},
        },
      );
      await transaction._seal();
      _control('COMMIT');
      return result;
    } on Object catch (error, stackTrace) {
      await transaction._seal();
      _rollback();
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      transaction._invalidate();
    }
  }

  void _control(String sql) {
    _runSqlite(() => _database.execute(sql), operation: 'transaction');
  }

  void _rollback() {
    try {
      _database.execute('ROLLBACK');
    } on Object {
      // Preserve the failure that caused the rollback.
    } finally {
      _synchronizeTotalChanges();
    }
  }

  sqlite.PreparedStatement _prepare(String sql) {
    return _runSqlite(
      () => _database.prepare(sql, checkNoTail: true),
      operation: 'prepare',
    );
  }

  int _refreshTotalChanges() {
    final current = _runSqlite(
      () =>
          _database.select('SELECT total_changes()').single.columnAt(0) as int,
      operation: 'read changes',
    );
    final delta = current - _totalChanges;
    _totalChanges = current;
    return delta;
  }

  void _synchronizeTotalChanges() {
    try {
      _refreshTotalChanges();
    } on Object {
      // Preserve the primary statement or rollback failure.
    }
  }
}

final class _TransactionExecutor implements SqlExecutor {
  _TransactionExecutor(this._owner);

  final SqliteDatabase _owner;
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
      return _owner._execute(statement, requireDirectWrite: true);
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
      'SQLite query cannot execute a statement declared as write.',
    );
  }
}

void _requireTopLevelExecute(BoundSql statement) {
  if (statement.kind == SqlStatementKind.rowReturning) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'SQLite execute cannot execute a statement declared as rowReturning.',
    );
  }
}

void _requireAtomicWrites(List<BoundSql> statements) {
  for (final statement in statements) {
    if (statement.kind != SqlStatementKind.write) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'SQLite atomicWrite requires kind: SqlStatementKind.write.',
      );
    }
  }
}

void _requireTransactionQuery(BoundSql statement) {
  if (statement.kind != SqlStatementKind.rowReturning) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'SQLite transaction query requires kind: '
      'SqlStatementKind.rowReturning.',
    );
  }
}

void _requireTransactionExecute(BoundSql statement) {
  if (statement.kind != SqlStatementKind.write) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'SQLite transaction execute requires kind: SqlStatementKind.write.',
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

final class _WriteObservation {
  bool _insert = false;
  bool _other = false;

  void add(sqlite.SqliteUpdateKind kind) {
    if (kind == sqlite.SqliteUpdateKind.insert) {
      _insert = true;
    } else {
      _other = true;
    }
  }

  bool get isDirectInsert => _insert && !_other;
}

({String sql, List<Object?> parameters}) _bind(BoundSql statement) {
  final sql = StringBuffer(statement.fragments.first);
  final parameters = <Object?>[];
  for (var index = 0; index < statement.values.length; index++) {
    sql
      ..write('?')
      ..write(statement.fragments[index + 1]);
    parameters.add(_writeValue(statement.values[index]));
  }
  return (sql: sql.toString(), parameters: parameters);
}

Object? _writeValue(SqlValue value) {
  return switch (value.value) {
    null => null,
    final int value => value,
    final double value => value,
    final String value => value,
    final bool value => value ? 1 : 0,
    final DateTime value => value.toUtc().toIso8601String(),
    final Uint8List value => value,
    final Object value => throw SqlException(
      SqlErrorCode.invalidValue,
      'SQLite cannot bind ${value.runtimeType}.',
    ),
  };
}

SqlValue _readValue(Object? value) {
  return switch (value) {
    null => const SqlValue.nullValue(),
    final int value => SqlValue.integer(value),
    final double value when value.isFinite => SqlValue.real(value),
    double() => throw const SqlException(
      SqlErrorCode.invalidRow,
      'SQLite returned a non-finite number.',
    ),
    final String value => SqlValue.text(value),
    final Uint8List value => SqlValue.blob(value),
    final Object value => throw SqlException(
      SqlErrorCode.invalidRow,
      'SQLite returned unsupported ${value.runtimeType} data.',
    ),
  };
}

T _runSqlite<T>(T Function() action, {required String operation}) {
  try {
    return action();
  } on SqlException {
    rethrow;
  } on sqlite.SqliteException catch (error) {
    throw _mapSqlite(error);
  } on ArgumentError {
    throw SqlException(SqlErrorCode.driver, 'SQLite $operation failed.');
  } on StateError {
    throw SqlException(SqlErrorCode.driver, 'SQLite $operation failed.');
  } on UnsupportedError {
    throw SqlException(SqlErrorCode.driver, 'SQLite $operation failed.');
  } on Exception catch (error) {
    throw SqlException(
      SqlErrorCode.driver,
      'SQLite $operation failed.',
      cause: error,
    );
  }
}

SqlException _mapSqlite(sqlite.SqliteException error) {
  final code = switch (error.resultCode) {
    sqlite.SqlError.SQLITE_CONSTRAINT => SqlErrorCode.constraint,
    sqlite.SqlError.SQLITE_MISMATCH ||
    sqlite.SqlError.SQLITE_RANGE ||
    sqlite.SqlError.SQLITE_TOOBIG => SqlErrorCode.invalidValue,
    sqlite.SqlError.SQLITE_BUSY ||
    sqlite.SqlError.SQLITE_LOCKED ||
    sqlite.SqlError.SQLITE_CANTOPEN ||
    sqlite.SqlError.SQLITE_IOERR ||
    sqlite.SqlError.SQLITE_FULL => SqlErrorCode.unavailable,
    _ => SqlErrorCode.driver,
  };
  return SqlException(
    code,
    switch (code) {
      SqlErrorCode.constraint => 'A SQLite constraint rejected the operation.',
      SqlErrorCode.invalidValue => 'SQLite rejected a bound value.',
      SqlErrorCode.unavailable => 'SQLite is unavailable.',
      _ => 'SQLite operation failed.',
    },
    constraint: code == SqlErrorCode.constraint
        ? _constraintName(error.message)
        : null,
    cause: sqlite.SqliteException(
      extendedResultCode: error.extendedResultCode,
      message: error.message,
      explanation: error.explanation,
      causingStatement: error.causingStatement,
      operation: error.operation,
      offset: error.offset,
    ),
  );
}

String? _constraintName(String message) {
  const marker = 'constraint failed:';
  final index = message.toLowerCase().indexOf(marker);
  if (index == -1) return null;
  final name = message.substring(index + marker.length).trim();
  return name.isEmpty ? null : name;
}

SqlException _closed() =>
    const SqlException(SqlErrorCode.closed, 'The SQLite database is closed.');
