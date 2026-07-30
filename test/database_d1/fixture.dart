@JS()
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:odroe/database_d1.dart';

@JS('d1BindingA')
external JSObject get _bindingA;

@JS('d1BindingB')
external JSObject get _bindingB;

@JS('d1SmokePassed')
external void _smokePassed();

@JS('d1SmokeFailed')
external void _smokeFailed(String message);

void main() {
  _run().then<void>(
    (_) => _smokePassed(),
    onError: (Object error, StackTrace stackTrace) {
      _smokeFailed('$error\n$stackTrace');
    },
  );
}

Future<void> _run() async {
  final first = D1SqlDatabase.fromBinding(_bindingA);
  final second = D1SqlDatabase.fromBinding(_bindingB);
  _expect(first is! TransactionalSqlDatabase, 'D1 must not be transactional');

  await first.execute(
    BoundSql.raw(
      'CREATE TABLE records '
      '(id INTEGER PRIMARY KEY, nullable INTEGER, count INTEGER, ratio REAL, '
      'name TEXT, active INTEGER, created_at TEXT, payload BLOB)',
    ),
  );

  final createdAt = DateTime.parse('2026-07-30T12:34:56.789+08:00');
  final inserted = await first.execute(
    BoundSql.parts(
      <String>[
        'INSERT INTO records '
            '(nullable, count, ratio, name, active, created_at, payload) '
            'VALUES (',
        ', ',
        ', ',
        ', ',
        ', ',
        ', ',
        ', ',
        ')',
      ],
      <SqlValue>[
        const SqlValue.nullValue(),
        const SqlValue.integer(7),
        SqlValue.real(1.5),
        const SqlValue.text('Odroe'),
        const SqlValue.boolean(true),
        SqlValue.time(createdAt),
        SqlValue.blob(Uint8List.fromList(<int>[0, 127, 255])),
      ],
    ),
  );
  _expect(inserted.affectedRows == 1, 'insert changes');
  _expect(inserted.lastInsertId == 1, 'insert row id');

  final record = (await first.query(
    BoundSql.raw(
      'SELECT id, nullable, count, ratio, name, active, created_at, payload '
      'FROM records',
      kind: SqlStatementKind.rowReturning,
    ),
    (row) => row,
  )).single;
  _expect(record.length == 8, 'record width');
  _expect(record.nameAt(0) == 'id', 'record column order');
  _expect(record.read(0, sqlInt) == 1, 'integer row value');
  _expect(record.valueAt(1).isNull, 'null row value');
  _expect(record.read(2, sqlInt) == 7, 'bound integer');
  _expect(record.read(3, sqlDouble) == 1.5, 'bound real');
  _expect(record.read(4, sqlText) == 'Odroe', 'bound text');
  _expect(record.read(5, sqlBool), 'bound boolean');
  _expect(
    record.read(6, sqlUtcDateTime) ==
        DateTime.parse('2026-07-30T04:34:56.789Z'),
    'UTC timestamp',
  );
  _expect(
    _sameBytes(record.read(7, sqlBlob), Uint8List.fromList(<int>[0, 127, 255])),
    'blob bytes',
  );

  final duplicate = (await first.query(
    BoundSql.raw(
      'SELECT 1 AS id, 2 AS id, 3 AS value',
      kind: SqlStatementKind.rowReturning,
    ),
    (row) => row,
  )).single;
  _expect(duplicate.nameAt(0) == 'id', 'first duplicate label');
  _expect(duplicate.nameAt(1) == 'id', 'second duplicate label');
  _expect(duplicate.read(0, sqlInt) == 1, 'first duplicate value');
  _expect(duplicate.read(1, sqlInt) == 2, 'second duplicate value');

  final literal = (await first.query(
    BoundSql.parts(
      <String>["SELECT '?' AS literal, ", ' AS value -- ?'],
      <SqlValue>[const SqlValue.integer(7)],
      kind: SqlStatementKind.rowReturning,
    ),
    (row) => row,
  )).single;
  _expect(literal.read(0, sqlText) == '?', 'literal placeholder');
  _expect(literal.read(1, sqlInt) == 7, 'anonymous placeholder');

  final updated = await first.execute(
    BoundSql.parts(
      <String>['UPDATE records SET active = ', ' WHERE id = ', ''],
      <SqlValue>[const SqlValue.boolean(false), const SqlValue.integer(1)],
    ),
  );
  _expect(updated.affectedRows == 1, 'update changes');
  _expect(updated.lastInsertId == null, 'update has no insert id');
  await _expectSqlCode(
    () => first.execute(BoundSql.raw('SELECT row_returning')),
    SqlErrorCode.unsupported,
    'row-returning execute',
  );
  await _expectSqlCode(
    () => first.query(
      BoundSql.raw('INSERT declared_write', kind: SqlStatementKind.write),
      (row) => row,
    ),
    SqlErrorCode.unsupported,
    'declared write query',
  );
  await _expectSqlCode(
    () => first.query(BoundSql.raw('INSERT unknown_query'), (row) => row),
    SqlErrorCode.unsupported,
    'unknown query',
  );
  await _expectSqlCode(
    () => first.execute(
      BoundSql.raw('SELECT declared_rows', kind: SqlStatementKind.rowReturning),
    ),
    SqlErrorCode.unsupported,
    'declared row-returning execute',
  );
  await _expectSqlCode(
    () => first.atomicWrite(<BoundSql>[BoundSql.raw('INSERT unknown_batch')]),
    SqlErrorCode.unsupported,
    'unknown batch statement',
  );

  final empty = await first.atomicWrite(const <BoundSql>[]);
  _expect(empty.isEmpty, 'empty batch');

  final batch = await first.atomicWrite(<BoundSql>[
    _insertTag('one'),
    _insertTag('two'),
  ]);
  _expect(batch.length == 2, 'batch result count');
  _expect(batch[0].lastInsertId == 1, 'first batch result');
  _expect(batch[1].lastInsertId == 2, 'second batch result');

  const secret = 'private@example.com';
  Object? constraint;
  StackTrace? constraintStack;
  try {
    await first.atomicWrite(<BoundSql>[_insertTag(secret), _insertTag(secret)]);
  } on Object catch (error, stackTrace) {
    constraint = error;
    constraintStack = stackTrace;
  }
  _expect(constraint is SqlException, 'constraint error type');
  final sqlError = constraint! as SqlException;
  _expect(sqlError.code == SqlErrorCode.constraint, 'constraint error code');
  _expect(!sqlError.message.contains(secret), 'constraint message redaction');
  _expect(!sqlError.toString().contains(secret), 'constraint string redaction');
  _expect(sqlError.cause == null, 'constraint cause redaction');
  _expect(
    !constraintStack.toString().contains(secret),
    'constraint stack redaction',
  );
  _expect(await _tagCount(first) == 2, 'failed batch rolled back');

  Object? driver;
  StackTrace? driverStack;
  try {
    await first.execute(
      BoundSql.parts(
        <String>['BROKEN ', ''],
        <SqlValue>[const SqlValue.text(secret)],
      ),
    );
  } on Object catch (error, stackTrace) {
    driver = error;
    driverStack = stackTrace;
  }
  _expect(driver is SqlException, 'driver error type');
  final driverError = driver! as SqlException;
  _expect(driverError.code == SqlErrorCode.driver, 'driver error code');
  _expect(!driverError.message.contains(secret), 'driver message redaction');
  _expect(!driverError.toString().contains(secret), 'driver string redaction');
  _expect(driverError.cause == null, 'driver cause redaction');
  _expect(!driverStack.toString().contains(secret), 'driver stack redaction');

  await _expectSqlCode(
    () => first.execute(
      BoundSql.parts(
        <String>['SELECT ', ''],
        <SqlValue>[const SqlValue.integer(9007199254740992)],
      ),
    ),
    SqlErrorCode.invalidValue,
    'unsafe bound integer',
  );
  await _expectSqlCode(
    () => first.query(
      BoundSql.raw(
        'SELECT invalid_number',
        kind: SqlStatementKind.rowReturning,
      ),
      (row) => row,
    ),
    SqlErrorCode.invalidRow,
    'non-finite row number',
  );
  await _expectSqlCode(
    () => first.execute(BoundSql.raw('INSERT unsafe_metadata')),
    SqlErrorCode.invalidRow,
    'unsafe metadata integer',
  );

  await Future.wait<void>(<Future<void>>[
    first.execute(_insertInstanceValue('first')).then((_) {}),
    second.execute(_insertInstanceValue('second')).then((_) {}),
  ]);
  _expect(await _instanceValue(first) == 'first', 'first binding isolation');
  _expect(await _instanceValue(second) == 'second', 'second binding isolation');

  final firstClose = first.close();
  final secondClose = first.close();
  _expect(identical(firstClose, secondClose), 'idempotent close future');
  await firstClose;
  await _expectSqlCode(
    () => first.query(
      BoundSql.raw(
        'SELECT instance_value',
        kind: SqlStatementKind.rowReturning,
      ),
      (row) => row,
    ),
    SqlErrorCode.closed,
    'closed database',
  );
  _expect(await _instanceValue(second) == 'second', 'close binding isolation');
  await second.close();
}

BoundSql _insertTag(String slug) {
  return BoundSql.parts(
    <String>['INSERT INTO tags (slug) VALUES (', ')'],
    <SqlValue>[SqlValue.text(slug)],
    kind: SqlStatementKind.write,
  );
}

BoundSql _insertInstanceValue(String value) {
  return BoundSql.parts(
    <String>['INSERT INTO instance_values (value) VALUES (', ')'],
    <SqlValue>[SqlValue.text(value)],
  );
}

Future<int> _tagCount(SqlDatabase database) async {
  return (await database.query(
    BoundSql.raw(
      'SELECT COUNT(*) AS count FROM tags',
      kind: SqlStatementKind.rowReturning,
    ),
    (row) => row.read(0, sqlInt),
  )).single;
}

Future<String> _instanceValue(SqlDatabase database) async {
  return (await database.query(
    BoundSql.raw('SELECT instance_value', kind: SqlStatementKind.rowReturning),
    (row) => row.read(0, sqlText),
  )).single;
}

Future<void> _expectSqlCode(
  Future<Object?> Function() action,
  SqlErrorCode code,
  String label,
) async {
  try {
    await action();
  } on SqlException catch (error) {
    _expect(error.code == code, label);
    return;
  }
  throw StateError('$label did not throw');
}

bool _sameBytes(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
