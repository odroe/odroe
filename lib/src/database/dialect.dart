import 'error.dart';

/// SQL compilation rules for one database family.
///
/// Cloudflare D1 uses [sqlite] because it exposes SQLite SQL syntax.
enum SqlDialect {
  /// SQLite and Cloudflare D1.
  sqlite,

  /// PostgreSQL.
  postgres,

  /// MySQL.
  mysql;

  /// Quotes one identifier without interpreting dots as qualification.
  String quoteIdentifier(String identifier) {
    _validateIdentifier(identifier, 'identifier');
    return switch (this) {
      SqlDialect.sqlite ||
      SqlDialect.postgres => '"${identifier.replaceAll('"', '""')}"',
      SqlDialect.mysql => '`${identifier.replaceAll('`', '``')}`',
    };
  }
}

/// Rejects an explicitly compiled [actual] dialect that differs from
/// [expected] for [database].
///
/// A `null` dialect is caller-authored SQL without a compatibility claim.
void requireSqlDialect(
  SqlDialect? actual,
  SqlDialect expected,
  String database,
) {
  if (actual == null || actual == expected) return;
  throw SqlException(
    SqlErrorCode.unsupported,
    '$database cannot execute SQL compiled for the ${actual.name} dialect.',
  );
}

/// Whether [dialect] supports SQL `RETURNING` in the typed query layer.
bool supportsSqlReturning(SqlDialect dialect) => dialect != SqlDialect.mysql;

void _validateIdentifier(String identifier, String kind) {
  if (identifier.isEmpty || identifier.contains('\u0000')) {
    throw ArgumentError.value(
      identifier,
      kind,
      'SQL identifiers must be non-empty and cannot contain NUL.',
    );
  }
}
