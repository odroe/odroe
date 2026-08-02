part of '../query.dart';

/// Dialect-explicit compiler for typed SQL operations.
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
    List<SqlJoin> joins = const <SqlJoin>[],
    SqlPredicate? where,
    List<SqlOrder> orderBy = const <SqlOrder>[],
    int? limit,
    int? offset,
  }) {
    return select<R>(
      from: table,
      projection: table.projection,
      joins: joins,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  /// Selects a custom [projection] from [from] and optional relational [joins].
  SqlRead<R> select<R>({
    required SqlTable<Object?> from,
    required SqlProjection<R> projection,
    List<SqlJoin> joins = const <SqlJoin>[],
    SqlPredicate? where,
    List<SqlOrder> orderBy = const <SqlOrder>[],
    int? limit,
    int? offset,
  }) {
    _validatePagination(limit, offset);
    final tables = _validateJoins(from, joins);
    final aliases = _selectAliases(tables, qualified: joins.isNotEmpty);
    _validateProjection(tables, projection);

    final builder = _BoundSqlBuilder(dialect)..write('SELECT ');
    _writeSelections(builder, projection.columns, aliases);
    builder
      ..write(' FROM ')
      ..write(_quoteTable(from));
    final fromAlias = aliases[from];
    if (fromAlias != null) {
      builder
        ..write(' AS ')
        ..write(dialect.quoteIdentifier(fromAlias));
    }
    for (final join in joins) {
      final alias = aliases[join.table]!;
      builder
        ..write(' ${join._kind.sql} ')
        ..write(_quoteTable(join.table))
        ..write(' AS ')
        ..write(dialect.quoteIdentifier(alias))
        ..write(' ON ');
      _writePredicate(builder, tables, aliases, join.on);
    }
    final predicate = where;
    if (predicate != null) {
      builder.write(' WHERE ');
      _writePredicate(builder, tables, aliases, predicate);
    }
    if (orderBy.isNotEmpty) {
      builder.write(' ORDER BY ');
      for (final (index, order) in orderBy.indexed) {
        if (index != 0) builder.write(', ');
        _requireColumnIn(tables, order._column);
        _writeColumnReference(builder, order._column, aliases);
        builder.write(order._descending ? ' DESC' : ' ASC');
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
    return SqlRead<R>._select(
      builder.build(kind: SqlStatementKind.rowReturning),
      projection.decode,
      limit: limit,
      offset: offset,
    );
  }

  /// Creates a single-row INSERT.
  ///
  /// Empty [values] use the selected dialect's default-row syntax.
  SqlWrite insert(SqlTable<Object?> table, Iterable<SqlAssignment> values) {
    final assignments = _validateAssignments(table, values);
    return _insert(table, assignments);
  }

  /// Creates one INSERT containing multiple rows.
  ///
  /// [rows] and every row must be non-empty. Every row must assign the same
  /// table columns, in the same order, as the first row. The complete input is
  /// validated before SQL is constructed.
  ///
  /// The returned write is one statement and can use [SqlWrite.returning] on
  /// dialects that support it. A database does not guarantee that returned rows
  /// follow the input order; correlate them by a stable key, never by input
  /// index. Callers remain responsible for keeping a batch within the selected
  /// database's bound-parameter limit.
  SqlWrite insertMany(
    SqlTable<Object?> table,
    Iterable<Iterable<SqlAssignment>> rows,
  ) {
    final validated = <List<SqlAssignment>>[];
    for (final row in rows) {
      final assignments = _validateAssignments(table, row);
      if (assignments.isEmpty) {
        throw ArgumentError(
          'Every row in a multi-row INSERT must be non-empty.',
        );
      }
      validated.add(assignments);
    }
    if (validated.isEmpty) {
      throw ArgumentError('A multi-row INSERT requires at least one row.');
    }

    final first = validated.first;
    for (final row in validated.skip(1)) {
      if (row.length != first.length) {
        throw ArgumentError(
          'Every row in a multi-row INSERT must assign the same columns in '
          'the same order.',
        );
      }
      for (var index = 0; index < first.length; index++) {
        if (!identical(row[index]._column, first[index]._column)) {
          throw ArgumentError(
            'Every row in a multi-row INSERT must assign the same columns in '
            'the same order.',
          );
        }
      }
    }
    return _insertMany(table, validated);
  }

  /// Creates a single-row INSERT that does nothing on a matching conflict.
  ///
  /// [values] and [target] must both be non-empty. Every target column must
  /// belong to [table]. The column list must match a conflict arbiter accepted
  /// by the selected database; use [BoundSql] for other index shapes.
  ///
  /// SQLite, Cloudflare D1, and PostgreSQL use conflict-target
  /// `ON CONFLICT DO NOTHING`. MySQL is rejected before database I/O because it
  /// has no equivalent conflict-target operation.
  SqlWrite insertOnConflictDoNothing(
    SqlTable<Object?> table,
    Iterable<SqlAssignment> values, {
    required Iterable<SqlTableColumn<Object?>> target,
  }) {
    if (!supportsSqlOnConflictDoNothing(dialect)) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'MySQL does not support conflict-target ON CONFLICT DO NOTHING.',
      );
    }
    final assignments = _validateAssignments(table, values);
    if (assignments.isEmpty) {
      throw ArgumentError(
        'A conflict-target SQL INSERT requires at least one assignment.',
      );
    }
    final columns = List<SqlTableColumn<Object?>>.unmodifiable(target);
    if (columns.isEmpty) {
      throw ArgumentError(
        'A SQL conflict target requires at least one column.',
      );
    }
    final names = <String>{};
    for (final column in columns) {
      _requireColumn(table, column);
      if (!names.add(column.name)) {
        throw ArgumentError(
          'Conflict target column "${column.name}" is used more than once.',
        );
      }
    }
    return _insert(table, assignments, conflictTarget: columns);
  }

  SqlWrite _insert(
    SqlTable<Object?> table,
    List<SqlAssignment> assignments, {
    List<SqlTableColumn<Object?>> conflictTarget =
        const <SqlTableColumn<Object?>>[],
  }) {
    final builder = _BoundSqlBuilder(dialect)
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
    if (conflictTarget.isNotEmpty) {
      builder.write(' ON CONFLICT (');
      for (final (index, column) in conflictTarget.indexed) {
        if (index != 0) builder.write(', ');
        builder.write(dialect.quoteIdentifier(column.name));
      }
      builder.write(') DO NOTHING');
    }
    return SqlWrite._(builder.build(kind: SqlStatementKind.write), table);
  }

  SqlWrite _insertMany(
    SqlTable<Object?> table,
    List<List<SqlAssignment>> rows,
  ) {
    final first = rows.first;
    final builder = _BoundSqlBuilder(dialect)
      ..write('INSERT INTO ')
      ..write(_quoteTable(table))
      ..write(' (');
    for (final (index, assignment) in first.indexed) {
      if (index != 0) builder.write(', ');
      builder.write(dialect.quoteIdentifier(assignment._column.name));
    }
    builder.write(') VALUES ');
    for (final (rowIndex, row) in rows.indexed) {
      if (rowIndex != 0) builder.write(', ');
      builder.write('(');
      for (final (columnIndex, assignment) in row.indexed) {
        if (columnIndex != 0) builder.write(', ');
        builder.bind(assignment._value);
      }
      builder.write(')');
    }
    return SqlWrite._(builder.build(kind: SqlStatementKind.write), table);
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
    final builder = _BoundSqlBuilder(dialect)
      ..write('DELETE FROM ')
      ..write(_quoteTable(table))
      ..write(' WHERE ');
    _writePredicate(
      builder,
      <SqlTable<Object?>>[table],
      const <SqlTable<Object?>, String>{},
      where,
    );
    return SqlWrite._(builder.build(kind: SqlStatementKind.write), table);
  }

  /// Creates an intentional full-table DELETE.
  SqlWrite deleteAll(SqlTable<Object?> table, {required SqlAllRows confirm}) {
    final builder = _BoundSqlBuilder(dialect)
      ..write('DELETE FROM ')
      ..write(_quoteTable(table));
    return SqlWrite._(builder.build(kind: SqlStatementKind.write), table);
  }

  SqlWrite _update(
    SqlTable<Object?> table,
    Iterable<SqlAssignment> values, {
    SqlPredicate? where,
  }) {
    final assignments = _validateAssignments(table, values);
    if (assignments.isEmpty) {
      throw ArgumentError('A SQL UPDATE requires at least one assignment.');
    }
    final builder = _BoundSqlBuilder(dialect)
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
      _writePredicate(
        builder,
        <SqlTable<Object?>>[table],
        const <SqlTable<Object?>, String>{},
        predicate,
      );
    }
    return SqlWrite._(builder.build(kind: SqlStatementKind.write), table);
  }

  List<SqlAssignment> _validateAssignments(
    SqlTable<Object?> table,
    Iterable<SqlAssignment> values,
  ) {
    final assignments = List<SqlAssignment>.unmodifiable(values);
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

  void _requireColumn(SqlTable<Object?> table, SqlTableColumn<Object?> column) {
    if (!identical(column.table, table)) {
      throw ArgumentError(
        'Column "${column.name}" does not belong to table "${table.name}".',
      );
    }
  }

  List<SqlTable<Object?>> _validateJoins(
    SqlTable<Object?> from,
    List<SqlJoin> joins,
  ) {
    final tables = <SqlTable<Object?>>[from];
    for (final join in joins) {
      if (_containsTable(tables, join.table)) {
        throw ArgumentError(
          'A SELECT cannot use the same table instance more than once. '
          'Create another "${join.table.name}" instance for a self join.',
        );
      }
      final scope = <SqlTable<Object?>>[...tables, join.table];
      final columns = _predicateColumns(join.on);
      for (final column in columns) {
        _requireColumnIn(scope, column);
      }
      if (!columns.any((column) => identical(column.table, join.table))) {
        throw ArgumentError(
          'JOIN condition must reference joined table "${join.table.name}".',
        );
      }
      if (!columns.any(
        (column) => tables.any((table) => identical(column.table, table)),
      )) {
        throw ArgumentError(
          'JOIN condition must reference a table already in the SELECT.',
        );
      }
      tables.add(join.table);
    }
    return List<SqlTable<Object?>>.unmodifiable(tables);
  }

  Map<SqlTable<Object?>, String> _selectAliases(
    List<SqlTable<Object?>> tables, {
    required bool qualified,
  }) {
    final aliases = Map<SqlTable<Object?>, String>.identity();
    if (qualified) {
      for (final (index, table) in tables.indexed) {
        aliases[table] = 't$index';
      }
    }
    return aliases;
  }

  void _validateProjection(
    List<SqlTable<Object?>> tables,
    SqlProjection<Object?> projection,
  ) {
    for (final selection in projection.columns) {
      _requireColumnIn(tables, selection._source);
    }
  }

  void _requireColumnIn(
    List<SqlTable<Object?>> tables,
    SqlTableColumn<Object?> column,
  ) {
    if (!tables.any((table) => identical(column.table, table))) {
      throw ArgumentError(
        'Column "${column.name}" is outside this SQL operation.',
      );
    }
  }

  bool _containsTable(
    List<SqlTable<Object?>> tables,
    SqlTable<Object?> candidate,
  ) => tables.any((table) => identical(table, candidate));

  void _writeSelections(
    _BoundSqlBuilder builder,
    List<SqlSelection<Object?>> selections,
    Map<SqlTable<Object?>, String> aliases,
  ) {
    for (final (index, selection) in selections.indexed) {
      if (index != 0) builder.write(', ');
      _writeColumnReference(builder, selection._source, aliases);
      final resultName = selection._resultColumn.name;
      if (resultName != selection._source.name) {
        builder
          ..write(' AS ')
          ..write(dialect.quoteIdentifier(resultName));
      }
    }
  }

  void _writePredicate(
    _BoundSqlBuilder builder,
    List<SqlTable<Object?>> tables,
    Map<SqlTable<Object?>, String> aliases,
    SqlPredicate predicate,
  ) {
    switch (predicate) {
      case _ComparisonPredicate():
        _requireColumnIn(tables, predicate.column);
        _writeColumnReference(builder, predicate.column, aliases);
        builder.write(' ${predicate.operator.sql} ');
        builder.bind(predicate.value);
      case _ColumnComparisonPredicate():
        _requireColumnIn(tables, predicate.left);
        _requireColumnIn(tables, predicate.right);
        _writeColumnReference(builder, predicate.left, aliases);
        builder.write(' ${predicate.operator.sql} ');
        _writeColumnReference(builder, predicate.right, aliases);
      case _NullPredicate():
        _requireColumnIn(tables, predicate.column);
        _writeColumnReference(builder, predicate.column, aliases);
        builder.write(predicate.negated ? ' IS NOT NULL' : ' IS NULL');
      case _MembershipPredicate():
        _requireColumnIn(tables, predicate.column);
        if (predicate.values.isEmpty) {
          builder.write('0 = 1');
          return;
        }
        _writeColumnReference(builder, predicate.column, aliases);
        builder.write(predicate.negated ? ' NOT IN (' : ' IN (');
        for (final (index, value) in predicate.values.indexed) {
          if (index != 0) builder.write(', ');
          builder.bind(value);
        }
        builder.write(')');
      case _LogicalPredicate():
        builder.write('(');
        _writePredicate(builder, tables, aliases, predicate.left);
        builder.write(' ${predicate.operator.sql} ');
        _writePredicate(builder, tables, aliases, predicate.right);
        builder.write(')');
    }
  }

  List<SqlTableColumn<Object?>> _predicateColumns(SqlPredicate predicate) {
    return switch (predicate) {
      _ComparisonPredicate() => <SqlTableColumn<Object?>>[predicate.column],
      _ColumnComparisonPredicate() => <SqlTableColumn<Object?>>[
        predicate.left,
        predicate.right,
      ],
      _NullPredicate() => <SqlTableColumn<Object?>>[predicate.column],
      _MembershipPredicate() => <SqlTableColumn<Object?>>[predicate.column],
      _LogicalPredicate() => <SqlTableColumn<Object?>>[
        ..._predicateColumns(predicate.left),
        ..._predicateColumns(predicate.right),
      ],
    };
  }

  void _writeColumnReference(
    _BoundSqlBuilder builder,
    SqlTableColumn<Object?> column,
    Map<SqlTable<Object?>, String> aliases,
  ) {
    final alias = aliases[column.table];
    if (alias != null) {
      builder
        ..write(dialect.quoteIdentifier(alias))
        ..write('.');
    }
    builder.write(dialect.quoteIdentifier(column.name));
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
///
/// For a mutation with `RETURNING`, the database applies the write before
/// projection decoding and cardinality checks. Use
/// [TransactionalSqlDatabase.transaction] where supported when either failure
/// must roll back the side effects. Otherwise, constrain the mutation so its
/// returned row count is already guaranteed.
final class SqlRead<R> {
  const SqlRead._(this.statement, this._decode)
    : _isSelect = false,
      _limit = null,
      _offset = null;

  const SqlRead._select(
    this.statement,
    this._decode, {
    required int? limit,
    required int? offset,
  }) : _isSelect = true,
       _limit = limit,
       _offset = offset;

  /// Bound statement available as an explicit low-level escape hatch.
  final BoundSql statement;

  final R Function(SqlRow row) _decode;
  final bool _isSelect;
  final int? _limit;
  final int? _offset;

  /// Executes this operation through [SqlExecutor.query].
  Future<List<R>> all(SqlExecutor executor) =>
      executor.query<R>(statement, _decode);

  /// Returns the only row produced by this operation.
  ///
  /// Throws [StateError] when the operation returns no rows or multiple rows.
  /// Typed `SELECT` operations fetch at most two rows for this check. An
  /// explicit query limit of zero, one, or two is preserved.
  Future<R> one(SqlExecutor executor) async {
    final rows = await _cardinalityRows(executor);
    if (rows.isEmpty) {
      throw StateError(
        'Expected exactly one SQL row, but no rows were returned.',
      );
    }
    if (rows.length > 1) {
      throw StateError(
        'Expected exactly one SQL row, but multiple rows were returned.',
      );
    }
    return _decode(rows.single);
  }

  /// Returns the only row produced by this operation, or `null` for no rows.
  ///
  /// Throws [StateError] when multiple rows are returned. Typed `SELECT`
  /// operations fetch at most two rows for this check. An explicit query limit
  /// of zero, one, or two is preserved.
  ///
  /// If [R] is nullable, `null` cannot distinguish no row from one row whose
  /// projection decodes to `null`; use [one] or [all] when that distinction
  /// matters.
  Future<R?> oneOrNull(SqlExecutor executor) async {
    final rows = await _cardinalityRows(executor);
    if (rows.length > 1) {
      throw StateError(
        'Expected at most one SQL row, but multiple rows were returned.',
      );
    }
    return rows.isEmpty ? null : _decode(rows.single);
  }

  Future<List<SqlRow>> _cardinalityRows(SqlExecutor executor) =>
      executor.query<SqlRow>(_cardinalityStatement(), _identityRow);

  BoundSql _cardinalityStatement() {
    if (!_isSelect || (_limit != null && _limit <= 2)) return statement;

    final fragments = List<String>.of(statement.fragments);
    final last = fragments.last;
    final currentSuffix = _limit == null
        ? ''
        : _paginationSuffix(_limit, _offset);
    if (currentSuffix.isNotEmpty && !last.endsWith(currentSuffix)) {
      throw StateError(
        'Typed SQL pagination does not match the compiled SELECT statement.',
      );
    }
    fragments[fragments.length - 1] =
        '${last.substring(0, last.length - currentSuffix.length)}'
        '${_paginationSuffix(2, _offset)}';
    return BoundSql.parts(
      fragments,
      statement.values,
      kind: statement.kind,
      dialect: statement.dialect,
    );
  }
}

/// A compiled non-row-returning INSERT, UPDATE, or DELETE.
final class SqlWrite {
  const SqlWrite._(this.statement, this._table);

  /// Bound statement available for direct execution or [SqlDatabase.atomicWrite].
  final BoundSql statement;

  final SqlTable<Object?> _table;

  /// Executes this operation through [SqlExecutor.execute].
  Future<SqlWriteResult> execute(SqlExecutor executor) =>
      executor.execute(statement);

  /// Adds a row-returning [projection] to this mutation.
  ///
  /// The result type exposes only row-returning terminals, so RETURNING
  /// statements cannot accidentally use [SqlExecutor.execute]. MySQL rejects
  /// this operation before any database call.
  SqlRead<R> returning<R>(SqlProjection<R> projection) {
    final dialect = statement.dialect!;
    if (!supportsSqlReturning(dialect)) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'MySQL does not support SQL RETURNING in this query layer.',
      );
    }
    for (final selection in projection.columns) {
      final column = selection._source;
      if (!identical(column.table, _table)) {
        throw ArgumentError(
          'Returning column "${column.name}" does not belong to '
          'table "${_table.name}".',
        );
      }
    }

    final fragments = List<String>.of(statement.fragments);
    final suffix = StringBuffer(' RETURNING ');
    for (final (index, selection) in projection.columns.indexed) {
      if (index != 0) suffix.write(', ');
      final column = selection._source;
      suffix.write(dialect.quoteIdentifier(column.name));
      final resultName = selection._resultColumn.name;
      if (resultName != column.name) {
        suffix
          ..write(' AS ')
          ..write(dialect.quoteIdentifier(resultName));
      }
    }
    fragments[fragments.length - 1] = '${fragments.last}${suffix.toString()}';
    return SqlRead<R>._(
      BoundSql.parts(
        fragments,
        statement.values,
        kind: SqlStatementKind.rowReturning,
        dialect: dialect,
      ),
      projection.decode,
    );
  }
}

String _paginationSuffix(int limit, int? offset) =>
    ' LIMIT $limit${offset == null ? '' : ' OFFSET $offset'}';

SqlRow _identityRow(SqlRow row) => row;

final class _BoundSqlBuilder {
  _BoundSqlBuilder(this._dialect);

  final SqlDialect _dialect;
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
    dialect: _dialect,
  );
}
