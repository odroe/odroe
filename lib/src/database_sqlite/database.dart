import 'dart:async';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../database/codec.dart';
import '../database/database.dart';
import '../database/dialect.dart';
import '../database/error.dart';
import '../database/result.dart';
import '../database/row.dart';
import '../database/statement.dart';
import 'migration.dart';

/// A native SQLite database with serialized access that enables and verifies
/// foreign-key enforcement when opening each connection.
final class SqliteDatabase implements TransactionalSqlDatabase {
  /// Opens the SQLite database at [path].
  factory SqliteDatabase.open(String path) {
    return SqliteDatabase._(
      _openSqliteDatabase(() => sqlite.sqlite3.open(path)),
    );
  }

  /// Opens a private in-memory SQLite database.
  factory SqliteDatabase.openInMemory() {
    return SqliteDatabase._(_openSqliteDatabase(sqlite.sqlite3.openInMemory));
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

  /// Applies pending native SQLite [migrations] in numeric order.
  ///
  /// Each complete SQL script and its history row commit atomically. Applied
  /// SQL strings are verified exactly and must never be edited, removed, or
  /// renamed. Returns the number of migrations applied by this call.
  Future<int> applyMigrations(Iterable<SqliteMigration> migrations) {
    final snapshot = List<SqliteMigration>.unmodifiable(migrations);
    return _schedule(() => _applyMigrations(snapshot));
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

  int _applyMigrations(Iterable<SqliteMigration> source) {
    final migrations = source.toList(growable: false)
      ..sort((left, right) {
        final version = left.version.compareTo(right.version);
        return version == 0 ? left.name.compareTo(right.name) : version;
      });
    for (var index = 1; index < migrations.length; index++) {
      if (migrations[index - 1].version == migrations[index].version) {
        throw SqliteMigrationException(
          'Migration version ${migrations[index].version} is duplicated.',
        );
      }
    }
    for (final migration in migrations) {
      _validateMigrationScript(migration);
    }

    _runMigrationOperation(
      () => _database.execute('PRAGMA writable_schema = OFF'),
      message: 'Could not secure the SQLite migration connection.',
    );
    _runMigrationOperation(
      () => _database.execute(_createMigrationHistorySql),
      message: 'Could not initialize the SQLite migration history.',
    );
    var appliedVersions = _verifyMigrationHistory(migrations);
    var observedDataVersion = _databaseDataVersion();
    var verifiedUnderWriteLock = false;

    var applied = 0;
    for (final migration in migrations) {
      if (appliedVersions.contains(migration.version)) continue;

      final previousCommitFilter = _database.commitFilter;
      var allowCommit = false;
      _database.commitFilter = () {
        return allowCommit && (previousCommitFilter?.call() ?? true);
      };
      try {
        _control('BEGIN IMMEDIATE');
        final dataVersion = _databaseDataVersion();
        if (!verifiedUnderWriteLock ||
            dataVersion != observedDataVersion ||
            _migrationHistoryCount() != appliedVersions.length) {
          appliedVersions = _verifyMigrationHistory(migrations);
          observedDataVersion = dataVersion;
          verifiedUnderWriteLock = true;
        }
        if (appliedVersions.contains(migration.version)) {
          allowCommit = true;
          _control('COMMIT');
          continue;
        }
        final historyCount = _migrationHistoryCount();
        _runMigrationOperation(
          () => _executeMigrationScript(migration),
          message: 'Migration failed and was rolled back.',
          migration: migration.name,
        );
        if (_database.autocommit || _migrationHistoryCount() != historyCount) {
          throw SqliteMigrationException(
            'Migration scripts cannot modify the Odroe migration history.',
            migration: migration.name,
          );
        }
        _verifyMigrationHistorySchema();
        _runMigrationOperation(
          () => _database.execute(
            'INSERT INTO main._odroe_migrations (version, name, sql) '
            'VALUES (?, ?, ?)',
            <Object?>[migration.version, migration.name, migration.sql],
          ),
          message: 'Migration history could not be recorded.',
          migration: migration.name,
        );
        final recorded = _readMigration(migration.version);
        if (recorded == null || _migrationHistoryCount() != historyCount + 1) {
          throw SqliteMigrationException(
            'Migration history could not be verified before commit.',
            migration: migration.name,
          );
        }
        _verifyMigration(migration, recorded);
        allowCommit = true;
        _control('COMMIT');
        appliedVersions.add(migration.version);
        observedDataVersion = _databaseDataVersion();
        applied++;
      } on Object catch (error, stackTrace) {
        _rollback();
        final failure = error is SqliteMigrationException
            ? error
            : SqliteMigrationException(
                'Migration failed and was rolled back.',
                migration: migration.name,
                cause: error,
              );
        Error.throwWithStackTrace(failure, stackTrace);
      } finally {
        _database.commitFilter = previousCommitFilter;
        _synchronizeTotalChanges();
      }
    }
    return applied;
  }

  Set<int> _verifyMigrationHistory(List<SqliteMigration> migrations) {
    _verifyMigrationHistorySchema();
    final available = <int, SqliteMigration>{
      for (final migration in migrations) migration.version: migration,
    };
    final rows = _readMigrationHistory();
    final appliedVersions = <int>{};
    var latest = 0;
    for (final applied in rows) {
      appliedVersions.add(applied.version);
      final migration = available[applied.version];
      if (migration == null) {
        throw SqliteMigrationException(
          'Applied migration ${applied.name} is missing or was renamed.',
          migration: applied.name,
        );
      }
      _verifyMigration(migration, applied);
      latest = applied.version;
    }
    for (final migration in migrations) {
      if (migration.version < latest &&
          !appliedVersions.contains(migration.version)) {
        throw SqliteMigrationException(
          'A lower-numbered migration cannot be inserted after version '
          '$latest.',
          migration: migration.name,
        );
      }
    }
    return appliedVersions;
  }

  ({int version, String name, String sql})? _readMigration(int version) {
    final rows = _runMigrationOperation(
      () => _database.select(
        'SELECT version, name, sql '
        'FROM main._odroe_migrations WHERE version = ?',
        <Object?>[version],
      ),
      message: 'Could not read the SQLite migration history.',
    );
    return rows.isEmpty ? null : _migrationRow(rows.single);
  }

  ({int version, String name, String sql}) _migrationRow(sqlite.Row row) {
    final version = row.columnAt(0);
    final name = row.columnAt(1);
    final sql = row.columnAt(2);
    if (version is! int || name is! String || sql is! String) {
      throw const SqliteMigrationException(
        'The SQLite migration history has an invalid shape.',
      );
    }
    return (version: version, name: name, sql: sql);
  }

  List<_MigrationRecord> _readMigrationHistory() {
    final rows = _runMigrationOperation(
      () => _database.select(
        'SELECT version, name, sql '
        'FROM main._odroe_migrations ORDER BY version',
      ),
      message: 'Could not read the SQLite migration history.',
    );
    return <_MigrationRecord>[for (final row in rows) _migrationRow(row)];
  }

  int _migrationHistoryCount() {
    final value = _runMigrationOperation(
      () => _database
          .select('SELECT count(*) FROM main._odroe_migrations')
          .single
          .columnAt(0),
      message: 'Could not read the SQLite migration history.',
    );
    if (value is! int) {
      throw const SqliteMigrationException(
        'The SQLite migration history has an invalid shape.',
      );
    }
    return value;
  }

  int _databaseDataVersion() {
    final value = _runMigrationOperation(
      () => _database.select('PRAGMA main.data_version').single.columnAt(0),
      message: 'Could not read the SQLite data version.',
    );
    if (value is! int) {
      throw const SqliteMigrationException(
        'SQLite returned an invalid data version.',
      );
    }
    return value;
  }

  void _executeMigrationScript(SqliteMigration migration) {
    var remaining = migration.sql;
    while (true) {
      late final sqlite.PreparedStatement statement;
      try {
        statement = _database.prepare(remaining);
      } on ArgumentError {
        return;
      }
      final consumed = statement.sql.length;
      try {
        final keyword = _firstSqlWord(statement.sql);
        if (keyword == 'pragma' && _changesForeignKeysPragma(statement.sql)) {
          throw SqliteMigrationException(
            'Migration scripts cannot change SQLite foreign-key enforcement.',
            migration: migration.name,
          );
        }
        if (_forbiddenMigrationStatements.contains(keyword)) {
          throw SqliteMigrationException(
            'Migration scripts cannot control transactions or connections.',
            migration: migration.name,
          );
        }
        statement.execute();
      } finally {
        statement.close();
      }
      if (consumed <= 0 || consumed > remaining.length) {
        throw SqliteMigrationException(
          'SQLite could not advance through the migration script.',
          migration: migration.name,
        );
      }
      remaining = remaining.substring(consumed);
    }
  }

  void _verifyMigrationHistorySchema() {
    final objects =
        <
          ({String schema, String type, String name, String table, String? sql})
        >[];
    for (final schema in const <String>['main', 'temp']) {
      final rows = _runMigrationOperation(
        () => _database.select(
          'SELECT type, name, tbl_name, sql FROM $schema.sqlite_master',
        ),
        message: 'Could not verify the SQLite migration history schema.',
      );
      for (final row in rows) {
        final type = row.columnAt(0);
        final name = row.columnAt(1);
        final table = row.columnAt(2);
        final sql = row.columnAt(3);
        if (type is! String ||
            name is! String ||
            table is! String ||
            (sql != null && sql is! String)) {
          throw const SqliteMigrationException(
            'SQLite returned an invalid schema record.',
          );
        }
        objects.add((
          schema: schema,
          type: type,
          name: name,
          table: table,
          sql: sql,
        ));
      }
    }

    var foundTable = false;
    var foundIndex = false;
    for (final object in objects) {
      if (object.schema == 'main' &&
          object.type == 'table' &&
          object.name == _migrationHistoryTable &&
          object.table == _migrationHistoryTable) {
        if (foundTable ||
            object.sql == null ||
            _normalizeSql(object.sql!) !=
                _normalizeSql(_migrationHistorySchemaSql)) {
          throw const SqliteMigrationException(
            'The SQLite migration history schema was modified.',
          );
        }
        foundTable = true;
        continue;
      }
      if (object.schema == 'main' &&
          object.type == 'index' &&
          object.name == _migrationHistoryIndex &&
          object.table == _migrationHistoryTable &&
          object.sql == null) {
        if (foundIndex) {
          throw const SqliteMigrationException(
            'The SQLite migration history schema was modified.',
          );
        }
        foundIndex = true;
        continue;
      }
      if (object.name.toLowerCase() == _migrationHistoryTable ||
          object.table.toLowerCase() == _migrationHistoryTable ||
          _mentionsMigrationHistory(object.sql)) {
        throw const SqliteMigrationException(
          'The SQLite migration history schema was modified.',
        );
      }
    }
    if (!foundTable || !foundIndex) {
      throw const SqliteMigrationException(
        'The SQLite migration history schema has an invalid shape.',
      );
    }
  }

  void _verifyMigration(
    SqliteMigration migration,
    ({int version, String name, String sql}) applied,
  ) {
    if (applied.name != migration.name) {
      throw SqliteMigrationException(
        'Applied migration ${applied.name} was renamed.',
        migration: migration.name,
      );
    }
    if (applied.sql != migration.sql) {
      throw SqliteMigrationException(
        'An applied migration was edited. Add a new migration instead.',
        migration: migration.name,
      );
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

typedef _MigrationRecord = ({int version, String name, String sql});

sqlite.Database _openSqliteDatabase(sqlite.Database Function() open) {
  final database = _runSqlite(open, operation: 'open');
  try {
    _runSqlite(
      () => database.execute('PRAGMA foreign_keys = ON'),
      operation: 'enable foreign keys',
    );
    final foreignKeysEnabled = _runSqlite(
      () => database.select('PRAGMA foreign_keys').single.columnAt(0),
      operation: 'verify foreign keys',
    );
    if (foreignKeysEnabled != 1) {
      throw const SqlException(
        SqlErrorCode.driver,
        'SQLite foreign key enforcement could not be enabled.',
      );
    }
    _runSqlite(
      () => database.execute('PRAGMA busy_timeout = 5000'),
      operation: 'configure busy timeout',
    );
    return database;
  } on Object catch (error, stackTrace) {
    try {
      database.close();
    } on Object {
      // Preserve the configuration failure that made the connection unsafe.
    }
    Error.throwWithStackTrace(error, stackTrace);
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
  requireSqlDialect(statement.dialect, SqlDialect.sqlite, 'SQLite');
  if (statement.kind == SqlStatementKind.write) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'SQLite query cannot execute a statement declared as write.',
    );
  }
}

void _requireTopLevelExecute(BoundSql statement) {
  requireSqlDialect(statement.dialect, SqlDialect.sqlite, 'SQLite');
  if (statement.kind == SqlStatementKind.rowReturning) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'SQLite execute cannot execute a statement declared as rowReturning.',
    );
  }
}

void _requireAtomicWrites(List<BoundSql> statements) {
  for (final statement in statements) {
    requireSqlDialect(statement.dialect, SqlDialect.sqlite, 'SQLite');
    if (statement.kind != SqlStatementKind.write) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'SQLite atomicWrite requires kind: SqlStatementKind.write.',
      );
    }
  }
}

void _requireTransactionQuery(BoundSql statement) {
  requireSqlDialect(statement.dialect, SqlDialect.sqlite, 'SQLite');
  if (statement.kind != SqlStatementKind.rowReturning) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'SQLite transaction query requires kind: '
      'SqlStatementKind.rowReturning.',
    );
  }
}

void _requireTransactionExecute(BoundSql statement) {
  requireSqlDialect(statement.dialect, SqlDialect.sqlite, 'SQLite');
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
  } on SqliteMigrationException {
    rethrow;
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

T _runMigrationOperation<T>(
  T Function() action, {
  required String message,
  String? migration,
}) {
  try {
    return _runSqlite(action, operation: 'migration');
  } on SqliteMigrationException {
    rethrow;
  } on Object catch (error) {
    throw SqliteMigrationException(message, migration: migration, cause: error);
  }
}

const _migrationHistoryTable = '_odroe_migrations';
const _migrationHistoryIndex = 'sqlite_autoindex__odroe_migrations_1';
const _migrationHistorySchemaSql = '''
CREATE TABLE _odroe_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  sql TEXT NOT NULL,
  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT
''';
const _createMigrationHistorySql = '''
CREATE TABLE IF NOT EXISTS main._odroe_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  sql TEXT NOT NULL,
  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT
''';
const _forbiddenMigrationStatements = <String>{
  'attach',
  'begin',
  'commit',
  'detach',
  'end',
  'release',
  'rollback',
  'savepoint',
  'vacuum',
};
void _validateMigrationScript(SqliteMigration migration) {
  if (_mentionsMigrationHistory(migration.sql) ||
      migration.sql.toLowerCase().contains('writable_schema')) {
    throw SqliteMigrationException(
      'Migration scripts cannot modify the Odroe migration history.',
      migration: migration.name,
    );
  }
}

String _firstSqlWord(String sql) {
  for (final word in _sqlWords(sql)) {
    return word;
  }
  return '';
}

bool _changesForeignKeysPragma(String sql) {
  var start = _skipSqlTrivia(sql, 0);
  while (start < sql.length && sql.codeUnitAt(start) == 0x3b) {
    start = _skipSqlTrivia(sql, start + 1);
  }
  final pragma = _readSqlIdentifier(sql, start);
  if (pragma == null || pragma.value != 'pragma') return false;
  var name = _readSqlIdentifier(sql, pragma.next);
  if (name == null) return false;
  final afterName = _skipSqlTrivia(sql, name.next);
  if (afterName < sql.length && sql.codeUnitAt(afterName) == 0x2e) {
    name = _readSqlIdentifier(sql, afterName + 1);
    if (name == null) return false;
  }
  if (name.value != 'foreign_keys') return false;
  final operation = _skipSqlTrivia(sql, name.next);
  if (operation >= sql.length) return false;
  final code = sql.codeUnitAt(operation);
  return code == 0x28 || code == 0x3d;
}

({String value, int next})? _readSqlIdentifier(String sql, int start) {
  var index = _skipSqlTrivia(sql, start);
  if (index >= sql.length) return null;
  final opening = sql.codeUnitAt(index);
  if (opening == 0x27 ||
      opening == 0x22 ||
      opening == 0x60 ||
      opening == 0x5b) {
    final closing = opening == 0x5b ? 0x5d : opening;
    final value = StringBuffer();
    index++;
    while (index < sql.length) {
      final code = sql.codeUnitAt(index++);
      if (code != closing) {
        value.writeCharCode(code);
        continue;
      }
      if (index < sql.length && sql.codeUnitAt(index) == closing) {
        value.writeCharCode(closing);
        index++;
        continue;
      }
      return (value: value.toString().toLowerCase(), next: index);
    }
    return null;
  }
  if (!_isSqlWordCode(opening)) return null;
  final wordStart = index++;
  while (index < sql.length && _isSqlWordCode(sql.codeUnitAt(index))) {
    index++;
  }
  return (value: sql.substring(wordStart, index).toLowerCase(), next: index);
}

int _skipSqlTrivia(String sql, int start) {
  var index = start;
  while (index < sql.length) {
    final code = sql.codeUnitAt(index);
    if (code == 0x20 || code >= 0x09 && code <= 0x0d) {
      index++;
      continue;
    }
    if (code == 0x2d &&
        index + 1 < sql.length &&
        sql.codeUnitAt(index + 1) == 0x2d) {
      index += 2;
      while (index < sql.length) {
        final current = sql.codeUnitAt(index++);
        if (current == 0x0a || current == 0x0d) break;
      }
      continue;
    }
    if (code == 0x2f &&
        index + 1 < sql.length &&
        sql.codeUnitAt(index + 1) == 0x2a) {
      index += 2;
      while (index + 1 < sql.length &&
          !(sql.codeUnitAt(index) == 0x2a &&
              sql.codeUnitAt(index + 1) == 0x2f)) {
        index++;
      }
      index = index + 1 < sql.length ? index + 2 : sql.length;
      continue;
    }
    return index;
  }
  return index;
}

Iterable<String> _sqlWords(String sql) sync* {
  var index = 0;
  while (index < sql.length) {
    final next = _skipSqlTrivia(sql, index);
    if (next != index) {
      index = next;
      continue;
    }
    final code = sql.codeUnitAt(index);
    if (code == 0x27) {
      index = _skipQuotedSql(sql, index, 0x27);
      continue;
    }
    if (code == 0x22 || code == 0x60) {
      final quote = code;
      final start = ++index;
      while (index < sql.length && sql.codeUnitAt(index) != quote) {
        index++;
      }
      if (index > start) {
        yield sql.substring(start, index).toLowerCase();
      }
      index = index < sql.length ? index + 1 : index;
      continue;
    }
    if (code == 0x5b) {
      final start = ++index;
      while (index < sql.length && sql.codeUnitAt(index) != 0x5d) {
        index++;
      }
      if (index > start) {
        yield sql.substring(start, index).toLowerCase();
      }
      index = index < sql.length ? index + 1 : index;
      continue;
    }
    if (_isSqlWordCode(code)) {
      final start = index++;
      while (index < sql.length && _isSqlWordCode(sql.codeUnitAt(index))) {
        index++;
      }
      yield sql.substring(start, index).toLowerCase();
      continue;
    }
    index++;
  }
}

int _skipQuotedSql(String sql, int index, int quote) {
  index++;
  while (index < sql.length) {
    if (sql.codeUnitAt(index) != quote) {
      index++;
      continue;
    }
    if (index + 1 < sql.length && sql.codeUnitAt(index + 1) == quote) {
      index += 2;
      continue;
    }
    return index + 1;
  }
  return index;
}

bool _isSqlWordCode(int code) {
  return code == 0x5f ||
      code >= 0x30 && code <= 0x39 ||
      code >= 0x41 && code <= 0x5a ||
      code >= 0x61 && code <= 0x7a;
}

bool _mentionsMigrationHistory(String? sql) {
  return sql?.toLowerCase().contains(_migrationHistoryTable) ?? false;
}

String _normalizeSql(String sql) {
  return sql.trim().replaceAll(RegExp(r'\s+'), ' ');
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
