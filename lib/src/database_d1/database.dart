@JS()
library;

import 'dart:js_interop';
import 'dart:typed_data';

import '../database/codec.dart';
import '../database/database.dart';
import '../database/dialect.dart';
import '../database/error.dart';
import '../database/result.dart';
import '../database/row.dart';
import '../database/statement.dart';
import 'bind.dart';

const int _maxSafeInteger = 9007199254740991;

/// A typed SQL database backed by a Cloudflare D1 Worker binding.
///
/// The binding remains owned by the Worker runtime. Closing this adapter only
/// prevents this instance from starting more operations.
final class D1SqlDatabase implements SqlDatabase {
  /// Wraps one D1 database binding from a Worker's environment.
  D1SqlDatabase.fromBinding(JSObject binding)
    : _database = _D1Database(binding);

  final _D1Database _database;
  bool _closed = false;
  Future<void>? _closeFuture;

  /// Executes an explicitly row-returning D1 statement.
  ///
  /// D1's raw result does not expose enough shape metadata to distinguish an
  /// empty query from a write. Requiring [SqlStatementKind.rowReturning]
  /// prevents an unknown write from being sent through this terminal.
  @override
  Future<List<T>> query<T>(
    BoundSql statement,
    T Function(SqlRow row) decode,
  ) async {
    _ensureOpen();
    _requireTopLevelQuery(statement);
    final JSAny? raw;
    try {
      raw = await _prepare(
        statement,
      ).raw(_D1RawOptions(columnNames: true)).toDart;
    } on Object catch (error) {
      _throwD1(error);
    }

    final rows = _readRows(raw);
    return <T>[for (final row in rows) decode(row)];
  }

  /// Executes a D1 write and rejects results that contain returned rows.
  ///
  /// D1 cannot distinguish a write from a row-returning statement that
  /// happens to return zero rows. Callers must therefore follow [SqlExecutor]'s
  /// contract and use [query] for every potentially row-returning statement.
  @override
  Future<SqlWriteResult> execute(BoundSql statement) async {
    _ensureOpen();
    _requireTopLevelExecute(statement);
    final JSAny? result;
    try {
      result = await _prepare(statement).run().toDart;
    } on Object catch (error) {
      _throwD1(error);
    }
    return _readWriteResult(result);
  }

  @override
  Future<List<SqlWriteResult>> atomicWrite(List<BoundSql> statements) async {
    final copiedStatements = List<BoundSql>.unmodifiable(statements);
    _ensureOpen();
    _requireAtomicWrites(copiedStatements);
    if (copiedStatements.isEmpty) return const <SqlWriteResult>[];

    final JSArray<_D1PreparedStatement> prepared;
    try {
      prepared = <_D1PreparedStatement>[
        for (final statement in copiedStatements) _prepare(statement),
      ].toJS;
    } on Object catch (error) {
      _throwD1(error);
    }

    final JSAny? results;
    try {
      results = await _database.batch(prepared).toDart;
    } on Object catch (error) {
      _throwD1(error);
    }

    if (results == null || !results.isA<JSArray<JSAny?>>()) {
      throw const SqlException(
        SqlErrorCode.invalidRow,
        'D1 returned an invalid batch result.',
      );
    }
    final values = (results as JSArray<JSAny?>).toDart;
    if (values.length != copiedStatements.length) {
      throw const SqlException(
        SqlErrorCode.invalidRow,
        'D1 returned the wrong number of batch results.',
      );
    }
    return <SqlWriteResult>[
      for (final result in values) _readWriteResult(result),
    ];
  }

  @override
  Future<void> close() {
    _closed = true;
    return _closeFuture ??= Future<void>.value();
  }

  void _ensureOpen() {
    if (_closed) {
      throw const SqlException(
        SqlErrorCode.closed,
        'The D1 database is closed.',
      );
    }
  }

  _D1PreparedStatement _prepare(BoundSql statement) {
    final sql = StringBuffer(statement.fragments.first);
    final parameters = <JSAny?>[];
    for (var index = 0; index < statement.values.length; index++) {
      sql
        ..write('?')
        ..write(statement.fragments[index + 1]);
      parameters.add(_writeValue(statement.values[index].value));
    }

    final prepared = _database.prepare(sql.toString());
    if (parameters.isEmpty) return prepared;
    return _D1PreparedStatement(bindD1Parameters(prepared, parameters));
  }
}

void _requireTopLevelQuery(BoundSql statement) {
  requireSqlDialect(statement.dialect, SqlDialect.sqlite, 'D1');
  if (statement.kind != SqlStatementKind.rowReturning) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'D1 query requires kind: SqlStatementKind.rowReturning.',
    );
  }
}

void _requireTopLevelExecute(BoundSql statement) {
  requireSqlDialect(statement.dialect, SqlDialect.sqlite, 'D1');
  if (statement.kind == SqlStatementKind.rowReturning) {
    throw const SqlException(
      SqlErrorCode.unsupported,
      'D1 execute cannot execute a statement declared as rowReturning.',
    );
  }
}

void _requireAtomicWrites(List<BoundSql> statements) {
  for (final statement in statements) {
    requireSqlDialect(statement.dialect, SqlDialect.sqlite, 'D1');
    if (statement.kind != SqlStatementKind.write) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'D1 atomicWrite requires kind: SqlStatementKind.write.',
      );
    }
  }
}

JSAny? _writeValue(Object? value) {
  return switch (value) {
    null => null,
    final int value => _writeInteger(value),
    final double value when value.isFinite => value.toJS,
    double() => throw const SqlException(
      SqlErrorCode.invalidValue,
      'D1 numbers must be finite.',
    ),
    final String value => value.toJS,
    final bool value => (value ? 1 : 0).toJS,
    final DateTime value => value.toUtc().toIso8601String().toJS,
    final Uint8List value => value.toJS,
    _ => throw const SqlException(
      SqlErrorCode.invalidValue,
      'D1 cannot bind this SQL value type.',
    ),
  };
}

JSNumber _writeInteger(int value) {
  if (value < -_maxSafeInteger || value > _maxSafeInteger) {
    throw const SqlException(
      SqlErrorCode.invalidValue,
      'D1 integers must be JavaScript safe integers.',
    );
  }
  return value.toJS;
}

List<SqlRow> _readRows(JSAny? raw) {
  if (raw == null || !raw.isA<JSArray<JSAny?>>()) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'D1 returned an invalid query result.',
    );
  }
  final rows = (raw as JSArray<JSAny?>).toDart;
  if (rows.isEmpty) return const <SqlRow>[];

  final rawHeader = rows.first;
  if (rawHeader == null || !rawHeader.isA<JSArray<JSAny?>>()) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'D1 returned an invalid column header.',
    );
  }
  final header = (rawHeader as JSArray<JSAny?>).toDart;
  final columns = <String>[
    for (final value in header)
      if (value != null && value.isA<JSString>())
        (value as JSString).toDart
      else
        throw const SqlException(
          SqlErrorCode.invalidRow,
          'D1 returned a non-text column name.',
        ),
  ];

  return <SqlRow>[
    for (final rawRow in rows.skip(1))
      if (rawRow != null && rawRow.isA<JSArray<JSAny?>>())
        _readRow(columns, rawRow as JSArray<JSAny?>)
      else
        throw const SqlException(
          SqlErrorCode.invalidRow,
          'D1 returned an invalid row.',
        ),
  ];
}

SqlRow _readRow(List<String> columns, JSArray<JSAny?> raw) {
  final values = raw.toDart;
  if (values.length != columns.length) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'D1 returned a row with the wrong number of values.',
    );
  }
  return SqlRow(columns, <SqlValue>[
    for (final value in values) _readValue(value),
  ]);
}

SqlValue _readValue(JSAny? value) {
  if (value == null) return const SqlValue.nullValue();
  if (value.isA<JSString>()) {
    return SqlValue.text((value as JSString).toDart);
  }
  if (value.isA<JSNumber>()) {
    final number = (value as JSNumber).toDartDouble;
    if (!number.isFinite) {
      throw const SqlException(
        SqlErrorCode.invalidRow,
        'D1 returned a non-finite number.',
      );
    }
    if (number == number.truncateToDouble()) {
      if (number.abs() > _maxSafeInteger) {
        throw const SqlException(
          SqlErrorCode.invalidRow,
          'D1 returned an unsafe integer.',
        );
      }
      return SqlValue.integer(number.toInt());
    }
    return SqlValue.real(number);
  }
  if (value.isA<JSUint8Array>()) {
    return SqlValue.blob((value as JSUint8Array).toDart);
  }
  if (value.isA<JSArrayBuffer>()) {
    return SqlValue.blob((value as JSArrayBuffer).toDart.asUint8List());
  }
  if (value.isA<JSArray<JSAny?>>()) {
    return SqlValue.blob(
      Uint8List.fromList(<int>[
        for (final byte in (value as JSArray<JSAny?>).toDart)
          _readBlobByte(byte),
      ]),
    );
  }
  throw const SqlException(
    SqlErrorCode.invalidRow,
    'D1 returned an unsupported SQL value.',
  );
}

int _readBlobByte(JSAny? value) {
  if (value == null || !value.isA<JSNumber>()) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'D1 returned an invalid byte.',
    );
  }
  final number = (value as JSNumber).toDartDouble;
  if (!number.isFinite ||
      number < 0 ||
      number > 255 ||
      number != number.truncateToDouble()) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'D1 returned an invalid byte.',
    );
  }
  return number.toInt();
}

SqlWriteResult _readWriteResult(JSAny? raw) {
  if (raw == null || !raw.isA<JSObject>()) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'D1 returned invalid write metadata.',
    );
  }
  final result = _D1Result(raw as JSObject);
  final success = result.success;
  if (success == null || !success.isA<JSBoolean>()) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'D1 returned invalid write metadata.',
    );
  }
  if (!(success as JSBoolean).toDart) {
    throw const SqlException(
      SqlErrorCode.driver,
      'D1 could not execute the SQL statement.',
    );
  }
  final returnedRows = result.results;
  if (returnedRows != null) {
    if (!returnedRows.isA<JSArray<JSAny?>>()) {
      throw const SqlException(
        SqlErrorCode.invalidRow,
        'D1 returned invalid write results.',
      );
    }
    if ((returnedRows as JSArray<JSAny?>).toDart.isNotEmpty) {
      throw const SqlException(
        SqlErrorCode.unsupported,
        'Use query for D1 statements that return rows. The unknown statement '
        'may already have run.',
      );
    }
  }
  final rawMeta = result.meta;
  if (rawMeta == null || !rawMeta.isA<JSObject>()) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'D1 returned invalid write metadata.',
    );
  }
  final meta = _D1Meta(rawMeta as JSObject);
  final changes = _readMetadataInteger(meta.changes, 'changes');
  final insertId = _readMetadataInteger(meta.lastRowId, 'last_row_id');
  return SqlWriteResult(
    affectedRows: changes,
    lastInsertId: insertId == 0 ? null : insertId,
  );
}

int _readMetadataInteger(JSAny? value, String name) {
  if (value == null || !value.isA<JSNumber>()) {
    throw SqlException(
      SqlErrorCode.invalidRow,
      'D1 did not return numeric $name metadata.',
    );
  }
  final number = (value as JSNumber).toDartDouble;
  if (!number.isFinite ||
      number < 0 ||
      number > _maxSafeInteger ||
      number != number.truncateToDouble()) {
    throw SqlException(
      SqlErrorCode.invalidRow,
      'D1 returned invalid $name metadata.',
    );
  }
  return number.toInt();
}

Never _throwD1(Object error) {
  if (error is SqlException) {
    throw error;
  }
  final description = error.toString().trim().toLowerCase();
  final d1Error = _d1Detail(description, 'd1_error');
  final d1Constraint = _d1Detail(description, 'd1_constraint');
  final constraintDetail = d1Constraint ?? d1Error;
  final constraint =
      constraintDetail != null &&
      (constraintDetail.contains('constraint failed') ||
          constraintDetail.contains('unique constraint') ||
          constraintDetail.contains('foreign key constraint') ||
          constraintDetail.contains('not null constraint') ||
          constraintDetail.contains('check constraint'));
  // Keep this narrow: these are Cloudflare's documented retryable signals.
  // Generic timeout/reset text can instead mean an oversized or costly query.
  final unavailable =
      d1Error != null &&
      (d1Error.startsWith('network connection lost') ||
          d1Error.startsWith(
            'internal error while starting up d1 db storage caused object to be reset',
          ) ||
          d1Error.startsWith(
            'internal error in d1 db storage caused object to be reset',
          ) ||
          d1Error.startsWith('d1 db reset because its code was updated') ||
          d1Error.startsWith(
            'cannot resolve d1 db due to transient issue on remote node',
          ));
  final mapped = constraint
      ? const SqlException(
          SqlErrorCode.constraint,
          'D1 rejected a database constraint.',
        )
      : unavailable
      ? const SqlException(SqlErrorCode.unavailable, 'D1 is unavailable.')
      : const SqlException(
          SqlErrorCode.driver,
          'D1 could not execute the SQL operation.',
        );
  throw mapped;
}

String? _d1Detail(String description, String code) {
  for (final prefix in <String>['$code:', 'error: $code:']) {
    if (description.startsWith(prefix)) {
      return description.substring(prefix.length).trimLeft();
    }
  }
  return null;
}

extension type _D1Database(JSObject _) implements JSObject {
  external _D1PreparedStatement prepare(String query);

  external JSPromise<JSAny?> batch(JSArray<_D1PreparedStatement> statements);
}

extension type _D1PreparedStatement(JSObject _) implements JSObject {
  external JSPromise<JSAny?> run();

  external JSPromise<JSAny?> raw(_D1RawOptions options);
}

extension type _D1Result(JSObject _) implements JSObject {
  external JSAny? get success;

  external JSAny? get meta;

  external JSAny? get results;
}

extension type _D1Meta(JSObject _) implements JSObject {
  external JSAny? get changes;

  @JS('last_row_id')
  external JSAny? get lastRowId;
}

extension type _D1RawOptions._(JSObject _) implements JSObject {
  external factory _D1RawOptions({required bool columnNames});
}
