/// Stable categories for database failures.
enum SqlErrorCode {
  /// A value cannot be represented or encoded by the selected database.
  invalidValue,

  /// A returned row does not match its expected shape or codec.
  invalidRow,

  /// A database constraint rejected the operation.
  constraint,

  /// The selected database does not implement the requested operation.
  unsupported,

  /// The database is temporarily unavailable.
  unavailable,

  /// The operation used a database after it was closed.
  closed,

  /// A driver failure has no more specific portable classification.
  driver,
}

/// A database failure with a driver-independent [code].
final class SqlException implements Exception {
  /// Creates a classified SQL failure.
  const SqlException(this.code, this.message, {this.constraint, this.cause});

  /// Portable failure category.
  final SqlErrorCode code;

  /// Human-readable description without bound parameter values.
  final String message;

  /// Database constraint name, when the driver can identify it.
  final String? constraint;

  /// Original driver or codec failure, when available.
  final Object? cause;

  @override
  String toString() => 'SqlException(${code.name}): $message';
}
