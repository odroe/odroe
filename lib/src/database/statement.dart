import 'codec.dart';
import 'dialect.dart';

/// Declares the protocol shape of a transaction-safe SQL statement.
///
/// [rowReturning] is for transaction-safe statements that return rows,
/// including mutations with `RETURNING`. [write] is for transaction-safe
/// mutations that do not return rows. DDL, transaction-control SQL, and any
/// statement whose transaction safety is unknown must remain [unknown].
enum SqlStatementKind {
  /// Shape and transaction safety are not declared.
  unknown,

  /// A transaction-safe statement that returns rows.
  rowReturning,

  /// A transaction-safe mutation that does not return rows.
  write,
}

/// Immutable SQL fragments interleaved with typed bound values.
///
/// A driver inserts its native placeholder between each pair of [fragments].
/// Drivers do not parse or rewrite fragment contents, so placeholder-like text
/// inside strings and comments remains untouched.
final class BoundSql {
  /// Creates a statement without bound parameters.
  ///
  /// [trustedSql] must be application-authored SQL. User input must instead be
  /// supplied through [BoundSql.parts].
  factory BoundSql.raw(
    String trustedSql, {
    SqlStatementKind kind = SqlStatementKind.unknown,
    SqlDialect? dialect,
  }) => BoundSql._(
    List<String>.unmodifiable(<String>[trustedSql]),
    const <SqlValue>[],
    kind,
    dialect,
  );

  /// Creates SQL from [fragments] separated by [values].
  ///
  /// The number of fragments must be exactly one greater than the number of
  /// values. Both lists are defensively copied.
  factory BoundSql.parts(
    List<String> fragments,
    List<SqlValue> values, {
    SqlStatementKind kind = SqlStatementKind.unknown,
    SqlDialect? dialect,
  }) {
    final copiedFragments = List<String>.unmodifiable(fragments);
    final copiedValues = List<SqlValue>.unmodifiable(values);
    if (copiedFragments.length != copiedValues.length + 1) {
      throw ArgumentError(
        'BoundSql requires exactly one more fragment than bound values.',
      );
    }
    return BoundSql._(copiedFragments, copiedValues, kind, dialect);
  }

  const BoundSql._(this.fragments, this.values, this.kind, this.dialect);

  /// Trusted SQL fragments in source order.
  final List<String> fragments;

  /// Bound values inserted between [fragments], in source order.
  final List<SqlValue> values;

  /// Declared protocol shape and transaction-safety category.
  final SqlStatementKind kind;

  /// Database dialect this statement was compiled for.
  ///
  /// `null` means caller-authored SQL without a compatibility claim. Drivers
  /// accept unpinned statements and reject only explicit dialect mismatches.
  final SqlDialect? dialect;
}
