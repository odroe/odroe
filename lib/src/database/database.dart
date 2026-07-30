import 'result.dart';
import 'row.dart';
import 'statement.dart';

/// Executes typed SQL without owning the underlying database resource.
///
/// Transaction callbacks receive this narrow view, so they cannot close the
/// parent database or start an unrelated atomic batch.
abstract interface class SqlExecutor {
  /// Executes a row-returning [statement] and decodes every row in order.
  ///
  /// Use this method for `SELECT` and dialect-supported statements containing
  /// `RETURNING`. The driver invokes [decode] exactly once per returned row.
  /// The terminal is part of the caller contract: some database protocols only
  /// reveal the result shape after execution, so choosing the wrong terminal
  /// can still apply a statement's side effects before it is rejected.
  Future<List<T>> query<T>(BoundSql statement, T Function(SqlRow row) decode);

  /// Executes one write [statement].
  ///
  /// Row-returning statements must use [query].
  Future<SqlWriteResult> execute(BoundSql statement);
}

/// Minimal typed SQL transport implemented by database drivers.
abstract interface class SqlDatabase implements SqlExecutor {
  /// Executes transaction-safe DML [statements] as one atomic write batch.
  ///
  /// Every statement must declare [SqlStatementKind.write]. An empty batch is
  /// valid and returns an empty result without starting a transaction.
  ///
  /// Results preserve input order. Either every statement commits or none do.
  /// Transaction control, DDL that implicitly commits, and row-returning
  /// statements are outside this contract.
  Future<List<SqlWriteResult>> atomicWrite(List<BoundSql> statements);

  /// Releases resources owned by this database.
  ///
  /// Implementations must allow this method to be called more than once.
  Future<void> close();
}

/// Optional capability for databases with interactive transactions.
///
/// Check this capability with `database is TransactionalSqlDatabase`. Atomic
/// write batches remain available through [SqlDatabase.atomicWrite] even when
/// this interface is not implemented.
abstract interface class TransactionalSqlDatabase implements SqlDatabase {
  /// Runs [action] inside one database transaction.
  ///
  /// The transaction commits when [action] completes and rolls back when it
  /// throws. Drivers invalidate the callback executor after [action] returns.
  /// Callback [SqlExecutor.query] calls require
  /// [SqlStatementKind.rowReturning], while [SqlExecutor.execute] calls require
  /// [SqlStatementKind.write].
  ///
  /// The callback must not issue transaction-control SQL or statements whose
  /// dialect implicitly commits, such as MySQL DDL.
  Future<T> transaction<T>(Future<T> Function(SqlExecutor transaction) action);
}
