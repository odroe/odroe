import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:mysql_dart/mysql_client.dart' as mysql;

import '../database/codec.dart';
import '../database/database.dart';
import '../database/dialect.dart';
import '../database/error.dart';
import '../database/result.dart';
import '../database/row.dart';
import '../database/statement.dart';
import 'binding.dart';
import 'error.dart';
import 'value.dart';

/// A Preview MySQL/MariaDB database backed by one connection or a lazy pool.
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
    _validateConnectionOptions(
      port: port,
      connectTimeout: connectTimeout,
      collation: collation,
      preparedStatementCacheSize: preparedStatementCacheSize,
    );

    return MysqlDatabase._connection(
      await _openConnection(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
        useTls: useTls,
        tlsContext: tlsContext,
        allowPublicKeyRetrieval: allowPublicKeyRetrieval,
        connectTimeout: connectTimeout,
        collation: collation,
        preparedStatementCacheSize: preparedStatementCacheSize,
      ),
    );
  }

  /// Creates and owns a lazy MySQL or MariaDB connection pool.
  ///
  /// Each connection uses UTC and the same TLS and prepared-statement settings
  /// as [open]. Top-level operations can run concurrently, while one
  /// transaction always keeps one connection. Use [open] when one serialized
  /// connection is the cheaper and sufficient choice.
  ///
  /// [maxConnections] defaults to four physical connections.
  /// [maxPendingOperations] defaults to 32 calls waiting for capacity; a later
  /// call fails with [SqlErrorCode.unavailable]. [queueTimeout] defaults to ten
  /// seconds and covers only that queue wait. Once a connection opening starts,
  /// [connectTimeout] bounds its handshake and session setup instead.
  ///
  /// Separate top-level calls may use different physical sessions. Do not send
  /// manual transaction control or rely on a session-level `SET` across calls;
  /// use [transaction] for every multi-statement unit of work.
  static MysqlDatabase pool({
    required String host,
    int port = 3306,
    required String database,
    required String username,
    required String password,
    int maxConnections = 4,
    int maxPendingOperations = 32,
    Duration queueTimeout = const Duration(seconds: 10),
    bool useTls = true,
    SecurityContext? tlsContext,
    bool allowPublicKeyRetrieval = false,
    Duration connectTimeout = const Duration(seconds: 10),
    String collation = 'utf8mb4_general_ci',
    int preparedStatementCacheSize = 32,
  }) {
    _validateConnectionOptions(
      port: port,
      connectTimeout: connectTimeout,
      collation: collation,
      preparedStatementCacheSize: preparedStatementCacheSize,
    );
    if (maxConnections < 1) {
      throw ArgumentError.value(
        maxConnections,
        'maxConnections',
        'Must be greater than zero.',
      );
    }
    if (maxPendingOperations < 0) {
      throw ArgumentError.value(
        maxPendingOperations,
        'maxPendingOperations',
        'Must not be negative.',
      );
    }
    if (queueTimeout.inMilliseconds < 1) {
      throw ArgumentError.value(
        queueTimeout,
        'queueTimeout',
        'Must be at least one millisecond.',
      );
    }

    return MysqlDatabase._pool(
      _MysqlPool(
        maxConnections: maxConnections,
        maxPendingOperations: maxPendingOperations,
        queueTimeout: queueTimeout,
        open: () => _openConnection(
          host: host,
          port: port,
          database: database,
          username: username,
          password: password,
          useTls: useTls,
          tlsContext: tlsContext,
          allowPublicKeyRetrieval: allowPublicKeyRetrieval,
          connectTimeout: connectTimeout,
          collation: collation,
          preparedStatementCacheSize: preparedStatementCacheSize,
        ),
      ),
    );
  }

  MysqlDatabase._connection(this._connection) : _pool = null;

  MysqlDatabase._pool(this._pool) : _connection = null;

  static final Object _transactionZoneKey = Object();

  final mysql.MySQLConnection? _connection;
  final _MysqlPool? _pool;
  final _SerialExecutor _serial = _SerialExecutor();

  bool _closing = false;
  bool _singleConnectionUsable = true;
  Future<void>? _closeFuture;
  int _activePoolOperations = 0;
  Completer<void>? _poolOperationsDrained;

  @override
  Future<List<T>> query<T>(BoundSql statement, T Function(SqlRow row) decode) {
    return _schedule(() async {
      _requireTopLevelQuery(statement);
      final response = await _runConnection(
        (lease) => _send(lease.connection, statement, operation: 'query'),
      );
      return _decodeQuery(response, decode);
    });
  }

  @override
  Future<SqlWriteResult> execute(BoundSql statement) {
    return _schedule(() async {
      _requireTopLevelExecute(statement);
      final response = await _runConnection(
        (lease) => _send(lease.connection, statement, operation: 'execute'),
      );
      return _decodeExecute(response);
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
    final pool = _pool;
    return _closeFuture = pool == null
        ? _serial.run(() async {
            final connection = _connection!;
            if (!_singleConnectionUsable) {
              connection.getSocket().destroy();
              return;
            }
            if (!connection.connected) return;
            await runMysql(
              connection.close,
              operation: 'close',
              connected: true,
            );
          })
        : _closePool(pool);
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

  Future<T> _runConnection<T>(Future<T> Function(_MysqlLease lease) action) {
    final pool = _pool;
    if (pool != null) return pool.withConnection(action);
    if (!_singleConnectionUsable) return Future<T>.error(_unavailable());

    final lease = _MysqlLease(_connection!);
    return Future<T>.sync(() => action(lease)).whenComplete(() {
      if (!lease.reusable) {
        _singleConnectionUsable = false;
        lease.connection.getSocket().destroy();
      }
    });
  }

  List<T> _decodeQuery<T>(
    ({mysql.IResultSet result, bool binary}) response,
    T Function(SqlRow row) decode,
  ) {
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

  Future<SqlWriteResult> _execute(
    mysql.MySQLConnection connection,
    BoundSql statement,
  ) async {
    final response = await _send(connection, statement, operation: 'execute');
    return _decodeExecute(response);
  }

  SqlWriteResult _decodeExecute(
    ({mysql.IResultSet result, bool binary}) response,
  ) {
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

    return _runConnection((lease) => _atomicWriteOn(lease, statements));
  }

  Future<List<SqlWriteResult>> _atomicWriteOn(
    _MysqlLease lease,
    List<BoundSql> statements,
  ) async {
    final connection = lease.connection;
    try {
      await _control(connection, 'START TRANSACTION');
    } on Object {
      lease.discard();
      rethrow;
    }
    try {
      final results = <SqlWriteResult>[];
      for (final statement in statements) {
        results.add(await _execute(connection, statement));
      }
      await _control(connection, 'COMMIT');
      return results;
    } on Object catch (error, stackTrace) {
      if (!await _rollbackAfterFailure(connection)) lease.discard();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<T> _transaction<T>(
    Future<T> Function(SqlExecutor transaction) action,
  ) async {
    try {
      return await _runConnection((lease) => _transactionOn(lease, action));
    } on _TransactionCallbackFailure catch (failure) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }

  Future<T> _transactionOn<T>(
    _MysqlLease lease,
    Future<T> Function(SqlExecutor transaction) action,
  ) async {
    final connection = lease.connection;
    try {
      await _control(connection, 'START TRANSACTION');
    } on Object {
      lease.discard();
      rethrow;
    }
    final transaction = _TransactionExecutor(this, connection);
    try {
      final value = await runZoned(
        () async {
          try {
            return await action(transaction);
          } on Object catch (error, stackTrace) {
            throw _TransactionCallbackFailure(error, stackTrace);
          }
        },
        zoneValues: <Object?, Object?>{
          _transactionZoneKey: <MysqlDatabase>{..._transactionOwners, this},
        },
      );
      await transaction._seal();
      await _control(connection, 'COMMIT');
      return value;
    } on Object catch (error, stackTrace) {
      await transaction._seal();
      if (!await _rollbackAfterFailure(connection)) lease.discard();
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      transaction._invalidate();
    }
  }

  Future<void> _control(mysql.MySQLConnection connection, String sql) async {
    if (!connection.connected) {
      throw _unavailable();
    }
    final result = await runMysql(
      () => connection.execute(sql),
      operation: 'transaction',
      connected: connection.connected,
    );
    if (result.numOfColumns != 0 || result.next != null) {
      throw const SqlException(
        SqlErrorCode.driver,
        'MySQL returned an invalid transaction response.',
      );
    }
  }

  Future<bool> _rollbackAfterFailure(mysql.MySQLConnection connection) async {
    try {
      if (!connection.connected) return false;
      await _control(connection, 'ROLLBACK');
      return true;
    } on Object {
      // Preserve the operation that caused the rollback.
      return false;
    }
  }

  Future<({mysql.IResultSet result, bool binary})> _send(
    mysql.MySQLConnection connection,
    BoundSql statement, {
    required String operation,
  }) async {
    if (!connection.connected) throw _unavailable();
    final bound = bindMysql(statement);
    if (bound.parameters.isNotEmpty) {
      final result = await runMysql(
        () => connection.execute(bound.sql, bound.parameters),
        operation: operation,
        connected: connection.connected,
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
      () => connection.execute(bound.sql),
      operation: operation,
      connected: connection.connected,
    );
    return (result: result, binary: false);
  }

  Future<void> _closePool(_MysqlPool pool) async {
    if (_activePoolOperations != 0) {
      await (_poolOperationsDrained ??= Completer<void>()).future;
    }
    await pool.close();
  }

  void _completePoolOperation() {
    _activePoolOperations--;
    if (_activePoolOperations == 0) {
      _poolOperationsDrained?.complete();
    }
  }
}

final class _TransactionExecutor implements SqlExecutor {
  _TransactionExecutor(this._owner, this._connection);

  final MysqlDatabase _owner;
  final mysql.MySQLConnection _connection;
  final _SerialExecutor _serial = _SerialExecutor();
  bool _active = true;

  @override
  Future<List<T>> query<T>(BoundSql statement, T Function(SqlRow row) decode) {
    return _schedule(() async {
      _requireTransactionQuery(statement);
      final response = await _owner._send(
        _connection,
        statement,
        operation: 'query',
      );
      return _owner._decodeQuery(response, decode);
    });
  }

  @override
  Future<SqlWriteResult> execute(BoundSql statement) {
    return _schedule(() {
      _requireTransactionExecute(statement);
      return _owner._execute(_connection, statement);
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

final class _TransactionCallbackFailure {
  const _TransactionCallbackFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

void _requireTopLevelQuery(BoundSql statement) {
  requireSqlDialect(statement.dialect, SqlDialect.mysql, 'MySQL');
  if (statement.kind == SqlStatementKind.write) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'MySQL query cannot execute a statement declared as write.',
    );
  }
}

void _requireTopLevelExecute(BoundSql statement) {
  requireSqlDialect(statement.dialect, SqlDialect.mysql, 'MySQL');
  if (statement.kind == SqlStatementKind.rowReturning) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'MySQL execute cannot execute a statement declared as rowReturning.',
    );
  }
}

void _requireAtomicWrites(List<BoundSql> statements) {
  for (final statement in statements) {
    requireSqlDialect(statement.dialect, SqlDialect.mysql, 'MySQL');
    if (statement.kind != SqlStatementKind.write) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'MySQL atomicWrite requires kind: SqlStatementKind.write.',
      );
    }
  }
}

void _requireTransactionQuery(BoundSql statement) {
  requireSqlDialect(statement.dialect, SqlDialect.mysql, 'MySQL');
  if (statement.kind != SqlStatementKind.rowReturning) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'MySQL transaction query requires kind: '
      'SqlStatementKind.rowReturning.',
    );
  }
}

void _requireTransactionExecute(BoundSql statement) {
  requireSqlDialect(statement.dialect, SqlDialect.mysql, 'MySQL');
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

final class _MysqlLease {
  _MysqlLease(this.connection);

  final mysql.MySQLConnection connection;
  bool reusable = true;

  void discard() {
    reusable = false;
  }
}

/// A small bounded pool with no retries or concurrent session sharing.
///
/// Odroe owns every connection. Failed opens release capacity and advance the
/// queue, so one unavailable server cannot strand later callers.
final class _MysqlPool {
  _MysqlPool({
    required this.maxConnections,
    required this.maxPendingOperations,
    required this.queueTimeout,
    required this.open,
  });

  final int maxConnections;
  final int maxPendingOperations;
  final Duration queueTimeout;
  final Future<mysql.MySQLConnection> Function() open;
  final Queue<mysql.MySQLConnection> _idle = Queue<mysql.MySQLConnection>();
  final Queue<Completer<mysql.MySQLConnection>> _waiters =
      Queue<Completer<mysql.MySQLConnection>>();

  int _connectionCount = 0;
  bool _isClosed = false;

  Future<T> withConnection<T>(
    Future<T> Function(_MysqlLease lease) action,
  ) async {
    final connection = await _acquire();
    final lease = _MysqlLease(connection);
    try {
      return await action(lease);
    } finally {
      await _release(lease);
    }
  }

  Future<mysql.MySQLConnection> _acquire() {
    if (_isClosed) return Future<mysql.MySQLConnection>.error(_closed());
    if (_idle.isNotEmpty) return Future.value(_idle.removeFirst());
    if (_waiters.isEmpty && _connectionCount < maxConnections) return _create();
    if (_waiters.length >= maxPendingOperations) {
      return Future<mysql.MySQLConnection>.error(_poolSaturated());
    }

    final waiter = Completer<mysql.MySQLConnection>();
    _waiters.addLast(waiter);
    final timeout = Timer(queueTimeout, () {
      if (_waiters.remove(waiter)) {
        waiter.completeError(_poolAcquireTimeout());
      }
    });
    return waiter.future.whenComplete(timeout.cancel);
  }

  Future<mysql.MySQLConnection> _create() async {
    _connectionCount++;
    late final mysql.MySQLConnection connection;
    try {
      connection = await open();
    } on Object {
      _connectionCount--;
      _serveWaiters();
      rethrow;
    }
    if (_isClosed) {
      _connectionCount--;
      await _discardConnection(connection);
      throw _closed();
    }
    return connection;
  }

  Future<void> _release(_MysqlLease lease) async {
    final connection = lease.connection;
    if (_isClosed || !lease.reusable || !connection.connected) {
      await _discardConnection(connection);
      _connectionCount--;
      _serveWaiters();
      return;
    }

    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(connection);
    } else {
      _idle.addLast(connection);
    }
  }

  void _serveWaiters() {
    while (!_isClosed &&
        _waiters.isNotEmpty &&
        _connectionCount < maxConnections) {
      final waiter = _waiters.removeFirst();
      unawaited(
        _create().then<void>(
          waiter.complete,
          onError: (Object error, StackTrace stackTrace) {
            waiter.completeError(error, stackTrace);
          },
        ),
      );
    }
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(_closed());
    }

    Object? firstError;
    StackTrace? firstStackTrace;
    while (_idle.isNotEmpty) {
      final connection = _idle.removeFirst();
      _connectionCount--;
      try {
        if (connection.connected) {
          await runMysql(connection.close, operation: 'close', connected: true);
        } else {
          connection.getSocket().destroy();
        }
      } on Object catch (error, stackTrace) {
        connection.getSocket().destroy();
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }
}

Future<mysql.MySQLConnection> _openConnection({
  required String host,
  required int port,
  required String database,
  required String username,
  required String password,
  required bool useTls,
  required SecurityContext? tlsContext,
  required bool allowPublicKeyRetrieval,
  required Duration connectTimeout,
  required String collation,
  required int preparedStatementCacheSize,
}) async {
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
      () => connection.connect(
        timeoutMs: connectTimeout.inMilliseconds,
        setCharsetOnConnect: false,
      ),
      operation: 'connect',
      connected: connection.connected,
    );
    await runMysql(
      () => connection.execute(
        'SET @@collation_connection=$collation, '
        '@@character_set_client=utf8mb4, '
        '@@character_set_connection=utf8mb4, '
        '@@character_set_results=utf8mb4, '
        "@@session.time_zone='+00:00'",
        null,
        false,
        connectTimeout,
      ),
      operation: 'connect',
      connected: connection.connected,
    );
    return connection;
  } on Object {
    await _discardConnection(connection);
    rethrow;
  }
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

SqlException _poolSaturated() => const SqlException(
  SqlErrorCode.unavailable,
  'The MySQL pool pending queue is full.',
);

SqlException _poolAcquireTimeout() => const SqlException(
  SqlErrorCode.unavailable,
  'Timed out waiting for a MySQL pool connection.',
);

final RegExp _collationPattern = RegExp(r'^[A-Za-z0-9_]+$');

void _validateConnectionOptions({
  required int port,
  required Duration connectTimeout,
  required String collation,
  required int preparedStatementCacheSize,
}) {
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
}
