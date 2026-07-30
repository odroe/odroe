part of '../query.dart';

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

  bool get _supportsReturning => this != SqlDialect.mysql;
}

/// Dialect-explicit compiler for typed, single-table SQL operations.
///
/// This object stores no database or request state. Every terminal operation
/// receives its [SqlExecutor] explicitly.
final class SqlQueries {
  /// Creates a compiler for [dialect].
  const SqlQueries(this.dialect);

  /// Database dialect used for identifier quoting and capability checks.
  final SqlDialect dialect;

  /// Selects the default [SqlTable.projection] from [table].
  SqlRead<R> selectTable<R>(
    SqlTable<R> table, {
    SqlPredicate? where,
    List<SqlOrder> orderBy = const <SqlOrder>[],
    int? limit,
    int? offset,
  }) {
    return select<R>(
      from: table,
      projection: table.projection,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  /// Selects a custom [projection] from one [from] table.
  SqlRead<R> select<R>({
    required SqlTable<Object?> from,
    required SqlProjection<R> projection,
    SqlPredicate? where,
    List<SqlOrder> orderBy = const <SqlOrder>[],
    int? limit,
    int? offset,
  }) {
    _validatePagination(limit, offset);
    _validateProjection(from, projection);

    final builder = _BoundSqlBuilder()..write('SELECT ');
    _writeColumns(builder, projection.columns);
    builder
      ..write(' FROM ')
      ..write(_quoteTable(from));
    final predicate = where;
    if (predicate != null) {
      builder.write(' WHERE ');
      _writePredicate(builder, from, predicate);
    }
    if (orderBy.isNotEmpty) {
      builder.write(' ORDER BY ');
      for (final (index, order) in orderBy.indexed) {
        if (index != 0) builder.write(', ');
        _requireColumn(from, order._column);
        builder
          ..write(dialect.quoteIdentifier(order._column.name))
          ..write(order._descending ? ' DESC' : ' ASC');
      }
    }
    if (limit != null) {
      builder
        ..write(' LIMIT ')
        ..write('$limit');
      if (offset != null) {
        builder
          ..write(' OFFSET ')
          ..write('$offset');
      }
    }
    return SqlRead<R>._(
      builder.build(kind: SqlStatementKind.rowReturning),
      projection.decode,
    );
  }

  /// Creates a single-row INSERT.
  ///
  /// Empty [values] use the selected dialect's default-row syntax.
  SqlWrite insert(SqlTable<Object?> table, Iterable<SqlAssignment> values) {
    final assignments = _validateAssignments(table, values, allowEmpty: true);
    final builder = _BoundSqlBuilder()
      ..write('INSERT INTO ')
      ..write(_quoteTable(table));
    if (assignments.isEmpty) {
      builder.write(
        dialect == SqlDialect.mysql ? ' () VALUES ()' : ' DEFAULT VALUES',
      );
    } else {
      builder.write(' (');
      for (final (index, assignment) in assignments.indexed) {
        if (index != 0) builder.write(', ');
        builder.write(dialect.quoteIdentifier(assignment._column.name));
      }
      builder.write(') VALUES (');
      for (final (index, assignment) in assignments.indexed) {
        if (index != 0) builder.write(', ');
        builder.bind(assignment._value);
      }
      builder.write(')');
    }
    return SqlWrite._(
      builder.build(kind: SqlStatementKind.write),
      table,
      dialect,
    );
  }

  /// Creates an UPDATE constrained by [where].
  SqlWrite updateWhere(
    SqlTable<Object?> table,
    Iterable<SqlAssignment> values, {
    required SqlPredicate where,
  }) {
    return _update(table, values, where: where);
  }

  /// Creates an intentional full-table UPDATE.
  SqlWrite updateAll(
    SqlTable<Object?> table,
    Iterable<SqlAssignment> values, {
    required SqlAllRows confirm,
  }) {
    return _update(table, values);
  }

  /// Creates a DELETE constrained by [where].
  SqlWrite deleteWhere(SqlTable<Object?> table, {required SqlPredicate where}) {
    final builder = _BoundSqlBuilder()
      ..write('DELETE FROM ')
      ..write(_quoteTable(table))
      ..write(' WHERE ');
    _writePredicate(builder, table, where);
    return SqlWrite._(
      builder.build(kind: SqlStatementKind.write),
      table,
      dialect,
    );
  }

  /// Creates an intentional full-table DELETE.
  SqlWrite deleteAll(SqlTable<Object?> table, {required SqlAllRows confirm}) {
    final builder = _BoundSqlBuilder()
      ..write('DELETE FROM ')
      ..write(_quoteTable(table));
    return SqlWrite._(
      builder.build(kind: SqlStatementKind.write),
      table,
      dialect,
    );
  }

  SqlWrite _update(
    SqlTable<Object?> table,
    Iterable<SqlAssignment> values, {
    SqlPredicate? where,
  }) {
    final assignments = _validateAssignments(table, values, allowEmpty: false);
    final builder = _BoundSqlBuilder()
      ..write('UPDATE ')
      ..write(_quoteTable(table))
      ..write(' SET ');
    for (final (index, assignment) in assignments.indexed) {
      if (index != 0) builder.write(', ');
      builder
        ..write(dialect.quoteIdentifier(assignment._column.name))
        ..write(' = ');
      builder.bind(assignment._value);
    }
    final predicate = where;
    if (predicate != null) {
      builder.write(' WHERE ');
      _writePredicate(builder, table, predicate);
    }
    return SqlWrite._(
      builder.build(kind: SqlStatementKind.write),
      table,
      dialect,
    );
  }

  List<SqlAssignment> _validateAssignments(
    SqlTable<Object?> table,
    Iterable<SqlAssignment> values, {
    required bool allowEmpty,
  }) {
    final assignments = List<SqlAssignment>.unmodifiable(values);
    if (!allowEmpty && assignments.isEmpty) {
      throw ArgumentError('A SQL UPDATE requires at least one assignment.');
    }
    final names = <String>{};
    for (final assignment in assignments) {
      _requireColumn(table, assignment._column);
      if (!names.add(assignment._column.name)) {
        throw ArgumentError(
          'Column "${assignment._column.name}" is assigned more than once.',
        );
      }
    }
    return assignments;
  }

  void _validateProjection(
    SqlTable<Object?> table,
    SqlProjection<Object?> projection,
  ) {
    for (final column in projection.columns) {
      _requireColumn(table, column);
    }
  }

  void _requireColumn(SqlTable<Object?> table, SqlTableColumn<Object?> column) {
    if (!identical(column.table, table)) {
      throw ArgumentError(
        'Column "${column.name}" does not belong to table "${table.name}".',
      );
    }
  }

  void _writeColumns(
    _BoundSqlBuilder builder,
    List<SqlTableColumn<Object?>> columns,
  ) {
    for (final (index, column) in columns.indexed) {
      if (index != 0) builder.write(', ');
      builder.write(dialect.quoteIdentifier(column.name));
    }
  }

  void _writePredicate(
    _BoundSqlBuilder builder,
    SqlTable<Object?> table,
    SqlPredicate predicate,
  ) {
    switch (predicate) {
      case _ComparisonPredicate():
        _requireColumn(table, predicate.column);
        builder
          ..write(dialect.quoteIdentifier(predicate.column.name))
          ..write(' ${predicate.operator.sql} ');
        builder.bind(predicate.value);
      case _NullPredicate():
        _requireColumn(table, predicate.column);
        builder
          ..write(dialect.quoteIdentifier(predicate.column.name))
          ..write(predicate.negated ? ' IS NOT NULL' : ' IS NULL');
      case _LogicalPredicate():
        builder.write('(');
        _writePredicate(builder, table, predicate.left);
        builder.write(' ${predicate.operator.sql} ');
        _writePredicate(builder, table, predicate.right);
        builder.write(')');
    }
  }

  String _quoteTable(SqlTable<Object?> table) {
    final schema = table.schema;
    final name = dialect.quoteIdentifier(table.name);
    return schema == null ? name : '${dialect.quoteIdentifier(schema)}.$name';
  }

  void _validatePagination(int? limit, int? offset) {
    if (limit != null && limit < 0) {
      throw ArgumentError.value(limit, 'limit', 'Must not be negative.');
    }
    if (offset != null) {
      if (offset < 0) {
        throw ArgumentError.value(offset, 'offset', 'Must not be negative.');
      }
      if (limit == null) {
        throw ArgumentError.value(offset, 'offset', 'Requires a SQL limit.');
      }
    }
  }
}

/// A compiled row-returning operation.
final class SqlRead<R> {
  const SqlRead._(this.statement, this._decode);

  /// Bound statement available as an explicit low-level escape hatch.
  final BoundSql statement;

  final R Function(SqlRow row) _decode;

  /// Executes this operation through [SqlExecutor.query].
  Future<List<R>> all(SqlExecutor executor) =>
      executor.query<R>(statement, _decode);
}

/// A compiled non-row-returning INSERT, UPDATE, or DELETE.
final class SqlWrite {
  const SqlWrite._(this.statement, this._table, this._dialect);

  /// Bound statement available for direct execution or [SqlDatabase.atomicWrite].
  final BoundSql statement;

  final SqlTable<Object?> _table;
  final SqlDialect _dialect;

  /// Executes this operation through [SqlExecutor.execute].
  Future<SqlWriteResult> execute(SqlExecutor executor) =>
      executor.execute(statement);

  /// Adds a row-returning [projection] to this mutation.
  ///
  /// The result type exposes only [SqlRead.all], so RETURNING statements cannot
  /// accidentally use [SqlExecutor.execute]. MySQL rejects this operation
  /// before any database call.
  SqlRead<R> returning<R>(SqlProjection<R> projection) {
    if (!_dialect._supportsReturning) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'MySQL does not support SQL RETURNING in this query layer.',
      );
    }
    for (final column in projection.columns) {
      if (!identical(column.table, _table)) {
        throw ArgumentError(
          'Returning column "${column.name}" does not belong to '
          'table "${_table.name}".',
        );
      }
    }

    final fragments = List<String>.of(statement.fragments);
    final suffix = StringBuffer(' RETURNING ');
    for (final (index, column) in projection.columns.indexed) {
      if (index != 0) suffix.write(', ');
      suffix.write(_dialect.quoteIdentifier(column.name));
    }
    fragments[fragments.length - 1] = '${fragments.last}${suffix.toString()}';
    return SqlRead<R>._(
      BoundSql.parts(
        fragments,
        statement.values,
        kind: SqlStatementKind.rowReturning,
      ),
      projection.decode,
    );
  }
}

final class _BoundSqlBuilder {
  final List<StringBuffer> _fragments = <StringBuffer>[StringBuffer()];
  final List<SqlValue> _values = <SqlValue>[];

  void write(String text) {
    _fragments.last.write(text);
  }

  void bind(SqlValue value) {
    _values.add(value);
    _fragments.add(StringBuffer());
  }

  BoundSql build({required SqlStatementKind kind}) => BoundSql.parts(
    <String>[for (final fragment in _fragments) fragment.toString()],
    _values,
    kind: kind,
  );
}
