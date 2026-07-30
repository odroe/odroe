part of '../query.dart';

/// A manually declared SQL table with one default row projection.
///
/// Models remain plain Dart values. Subclasses declare columns with [column]
/// and decode rows through [projection]; no reflection or generated code is
/// involved.
abstract base class SqlTable<Row> {
  /// Creates a table named [name] in the optional [schema].
  SqlTable(this.name, {this.schema}) {
    _validateIdentifier(name, 'table');
    final schema = this.schema;
    if (schema != null) _validateIdentifier(schema, 'schema');
  }

  /// Physical table name, without a schema prefix.
  final String name;

  /// Optional physical schema name.
  final String? schema;

  /// Default ordered columns and decoder for one table row.
  SqlProjection<Row> get projection;

  /// Declares one physical table column.
  SqlTableColumn<T> column<T>(String name, SqlCodec<T> codec) {
    _validateIdentifier(name, 'column');
    return SqlTableColumn<T>._(
      this as SqlTable<Object?>,
      SqlColumn<T>(name, codec),
    );
  }
}

/// A table-owned SQL column with one statically fixed Dart value type.
final class SqlTableColumn<T> implements SqlSelection<T> {
  const SqlTableColumn._(this.table, this.resultColumn);

  /// Table that owns this column.
  final SqlTable<Object?> table;

  /// Named result decoder and value codec for this column.
  final SqlColumn<T> resultColumn;

  @override
  SqlTableColumn<Object?> get _source => this as SqlTableColumn<Object?>;

  @override
  SqlColumn<T> get _resultColumn => resultColumn;

  /// Physical column name.
  String get name => resultColumn.name;

  /// Dart-to-SQL value codec.
  SqlCodec<T> get codec => resultColumn.codec;

  /// Decodes this column from [row] at [index].
  @override
  T read(SqlRow row, int index) => resultColumn.read(row, index);

  /// Creates a type-safe INSERT or UPDATE assignment.
  ///
  /// The receiver fixes [T] before [value] is checked. The value is encoded
  /// before assignments of different column types share one list.
  SqlAssignment set(T value) => SqlAssignment._(
    this as SqlTableColumn<Object?>,
    resultColumn.bind(value),
  );

  /// Creates an equality predicate.
  ///
  /// A nullable `null` value compiles to `IS NULL`.
  SqlPredicate equals(T value) {
    if (value == null) return isNull;
    return _ComparisonPredicate(
      this as SqlTableColumn<Object?>,
      _ComparisonOperator.equal,
      resultColumn.bind(value),
    );
  }

  /// Creates an inequality predicate.
  ///
  /// A nullable `null` value compiles to `IS NOT NULL`.
  SqlPredicate notEquals(T value) {
    if (value == null) return isNotNull;
    return _ComparisonPredicate(
      this as SqlTableColumn<Object?>,
      _ComparisonOperator.notEqual,
      resultColumn.bind(value),
    );
  }

  /// Creates a type-safe equality predicate between two columns.
  ///
  /// Nullable and non-nullable columns with the same value type can be
  /// compared in either direction.
  SqlPredicate equalsColumn(SqlTableColumn<T?> other) =>
      _ColumnComparisonPredicate(
        this as SqlTableColumn<Object?>,
        _ComparisonOperator.equal,
        other as SqlTableColumn<Object?>,
      );

  /// Creates a type-safe inequality predicate between two columns.
  SqlPredicate notEqualsColumn(SqlTableColumn<T?> other) =>
      _ColumnComparisonPredicate(
        this as SqlTableColumn<Object?>,
        _ComparisonOperator.notEqual,
        other as SqlTableColumn<Object?>,
      );

  /// Creates a less-than predicate.
  SqlPredicate lessThan(T value) =>
      _orderedPredicate(_ComparisonOperator.lessThan, value);

  /// Creates a less-than-or-equal predicate.
  SqlPredicate lessThanOrEqual(T value) =>
      _orderedPredicate(_ComparisonOperator.lessThanOrEqual, value);

  /// Creates a greater-than predicate.
  SqlPredicate greaterThan(T value) =>
      _orderedPredicate(_ComparisonOperator.greaterThan, value);

  /// Creates a greater-than-or-equal predicate.
  SqlPredicate greaterThanOrEqual(T value) =>
      _orderedPredicate(_ComparisonOperator.greaterThanOrEqual, value);

  /// Tests this column for SQL `NULL`.
  SqlPredicate get isNull =>
      _NullPredicate(this as SqlTableColumn<Object?>, negated: false);

  /// Tests this column for a non-`NULL` SQL value.
  SqlPredicate get isNotNull =>
      _NullPredicate(this as SqlTableColumn<Object?>, negated: true);

  /// Orders this column from lowest to highest.
  SqlOrder get ascending =>
      SqlOrder._(this as SqlTableColumn<Object?>, descending: false);

  /// Orders this column from highest to lowest.
  SqlOrder get descending =>
      SqlOrder._(this as SqlTableColumn<Object?>, descending: true);

  SqlPredicate _orderedPredicate(_ComparisonOperator operator, T value) {
    if (value == null) {
      throw ArgumentError.value(
        value,
        'value',
        'Ordered SQL comparisons cannot use NULL.',
      );
    }
    return _ComparisonPredicate(
      this as SqlTableColumn<Object?>,
      operator,
      resultColumn.bind(value),
    );
  }
}

/// One typed column selected from a SQL result.
///
/// A selection keeps its physical source column separate from its result
/// codec. This lets a `LEFT JOIN` decode a non-nullable schema column as an
/// optional result without weakening INSERT and UPDATE types.
abstract interface class SqlSelection<T> {
  /// Decodes this selection from [row] at [index].
  T read(SqlRow row, int index);

  SqlTableColumn<Object?> get _source;
  SqlColumn<T> get _resultColumn;
}

/// Result-only modifiers for a selected SQL column.
extension SqlSelectionModifiers<T> on SqlSelection<T> {
  /// Decodes SQL `NULL` as `null`, typically for the right side of a
  /// `LEFT JOIN`.
  SqlSelection<T?> get optional => _SqlSelection<T?>._(
    _source,
    SqlColumn<T?>(_resultColumn.name, nullable(_resultColumn.codec)),
  );

  /// Gives this result column an explicit SQL alias.
  SqlSelection<T> as(String alias) {
    _validateIdentifier(alias, 'selection alias');
    return _SqlSelection<T>._(_source, _resultColumn.as(alias));
  }
}

final class _SqlSelection<T> implements SqlSelection<T> {
  const _SqlSelection._(this._source, this._resultColumn);

  @override
  final SqlTableColumn<Object?> _source;

  @override
  final SqlColumn<T> _resultColumn;

  @override
  T read(SqlRow row, int index) => _resultColumn.read(row, index);
}

/// Ordered selected columns and a decoder for one result value.
final class SqlProjection<R> {
  /// Creates a projection from [columns] in decoder order.
  factory SqlProjection(
    Iterable<SqlSelection<Object?>> columns,
    R Function(SqlRow row) decode,
  ) {
    final copied = List<SqlSelection<Object?>>.unmodifiable(columns);
    if (copied.isEmpty) {
      throw ArgumentError('A SQL projection requires at least one column.');
    }
    return SqlProjection<R>._(copied, decode);
  }

  /// Creates a scalar projection for one [column].
  factory SqlProjection.column(SqlSelection<R> column) {
    return SqlProjection<R>(<SqlSelection<Object?>>[
      column,
    ], (row) => column.read(row, 0));
  }

  const SqlProjection._(this.columns, this.decode);

  /// Selected columns in result order.
  final List<SqlSelection<Object?>> columns;

  /// Converts one ordered [SqlRow] into an application value.
  final R Function(SqlRow row) decode;
}

/// One heterogeneous, type-checked INSERT or UPDATE assignment.
///
/// Instances can only be created through [SqlTableColumn.set].
final class SqlAssignment {
  const SqlAssignment._(this._column, this._value);

  final SqlTableColumn<Object?> _column;
  final SqlValue _value;
}

/// One composable, bound SQL predicate.
sealed class SqlPredicate {
  const SqlPredicate._();

  /// Combines this predicate and [other] with SQL `AND`.
  SqlPredicate and(SqlPredicate other) =>
      _LogicalPredicate(this, _LogicalOperator.and, other);

  /// Combines this predicate and [other] with SQL `OR`.
  SqlPredicate or(SqlPredicate other) =>
      _LogicalPredicate(this, _LogicalOperator.or, other);
}

final class _ComparisonPredicate extends SqlPredicate {
  const _ComparisonPredicate(this.column, this.operator, this.value)
    : super._();

  final SqlTableColumn<Object?> column;
  final _ComparisonOperator operator;
  final SqlValue value;
}

final class _ColumnComparisonPredicate extends SqlPredicate {
  const _ColumnComparisonPredicate(this.left, this.operator, this.right)
    : super._();

  final SqlTableColumn<Object?> left;
  final _ComparisonOperator operator;
  final SqlTableColumn<Object?> right;
}

final class _NullPredicate extends SqlPredicate {
  const _NullPredicate(this.column, {required this.negated}) : super._();

  final SqlTableColumn<Object?> column;
  final bool negated;
}

final class _LogicalPredicate extends SqlPredicate {
  const _LogicalPredicate(this.left, this.operator, this.right) : super._();

  final SqlPredicate left;
  final _LogicalOperator operator;
  final SqlPredicate right;
}

enum _ComparisonOperator {
  equal('='),
  notEqual('<>'),
  lessThan('<'),
  lessThanOrEqual('<='),
  greaterThan('>'),
  greaterThanOrEqual('>=');

  const _ComparisonOperator(this.sql);

  final String sql;
}

enum _LogicalOperator {
  and('AND'),
  or('OR');

  const _LogicalOperator(this.sql);

  final String sql;
}

/// One typed column ordering clause.
final class SqlOrder {
  const SqlOrder._(this._column, {required bool descending})
    : _descending = descending;

  final SqlTableColumn<Object?> _column;
  final bool _descending;
}

/// One relational table join in a typed SELECT.
final class SqlJoin {
  /// Creates an `INNER JOIN`.
  const SqlJoin.inner(this.table, {required this.on})
    : _kind = _SqlJoinKind.inner;

  /// Creates a `LEFT JOIN`.
  const SqlJoin.left(this.table, {required this.on})
    : _kind = _SqlJoinKind.left;

  /// Joined table. Use another table instance for a self join.
  final SqlTable<Object?> table;

  /// Join condition.
  final SqlPredicate on;

  final _SqlJoinKind _kind;
}

enum _SqlJoinKind {
  inner('INNER JOIN'),
  left('LEFT JOIN');

  const _SqlJoinKind(this.sql);

  final String sql;
}

/// Explicit confirmation token for a full-table mutation.
final class SqlAllRows {
  const SqlAllRows._();
}

/// Confirms an intentional full-table UPDATE or DELETE.
///
/// Full-table methods also include `All` in their names, providing two visible
/// confirmations at the call site.
const SqlAllRows allRows = SqlAllRows._();

void _validateIdentifier(String identifier, String kind) {
  if (identifier.isEmpty || identifier.contains('\u0000')) {
    throw ArgumentError.value(
      identifier,
      kind,
      'SQL identifiers must be non-empty and cannot contain NUL.',
    );
  }
}
