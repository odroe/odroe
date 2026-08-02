@JS()
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:odroe/database_d1.dart';

@JS('globalThis')
external _GlobalThis get _globalThis;

void main() {
  _globalThis.odroeD1WorkerdTest = ((JSObject bindings) => _runFromBinding(
    bindings,
  )).toJS;
}

JSPromise<JSAny?> _runFromBinding(JSObject bindings) {
  return _run(_Environment(bindings)).then<JSAny?>((_) => null).toJS;
}

Future<void> _run(_Environment environment) async {
  final database = D1SqlDatabase.fromBinding(environment.database);
  _expect(
    database is! TransactionalSqlDatabase,
    'D1 must not expose interactive transactions',
  );

  try {
    await database.execute(
      BoundSql.raw('''
        CREATE TABLE records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nullable INTEGER,
          count INTEGER NOT NULL,
          ratio REAL NOT NULL,
          name TEXT NOT NULL,
          active INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          payload BLOB NOT NULL
        ) STRICT
      '''),
    );
    await database.execute(
      BoundSql.raw('''
        CREATE TABLE tags (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          slug TEXT NOT NULL UNIQUE
        ) STRICT
      '''),
    );
    await database.execute(
      BoundSql.raw('''
        CREATE TABLE conflict_records (
          id INTEGER PRIMARY KEY,
          value TEXT NOT NULL
        ) STRICT
      '''),
    );

    final conflictRecords = _ConflictRecords();
    const queries = SqlQueries(SqlDialect.sqlite);
    final conflictInsert = await queries
        .insertOnConflictDoNothing(
          conflictRecords,
          <SqlAssignment>[
            conflictRecords.id.set(1),
            conflictRecords.value.set('Original'),
          ],
          target: <SqlTableColumn<Object?>>[conflictRecords.id],
        )
        .execute(database);
    _expect(conflictInsert.affectedRows == 1, 'conflict insert changes');

    final ignoredConflict = await queries
        .insertOnConflictDoNothing(
          conflictRecords,
          <SqlAssignment>[
            conflictRecords.id.set(1),
            conflictRecords.value.set('Replacement'),
          ],
          target: <SqlTableColumn<Object?>>[conflictRecords.id],
        )
        .execute(database);
    _expect(ignoredConflict.affectedRows == 0, 'ignored conflict changes');

    final returnedConflict = await queries
        .insertOnConflictDoNothing(
          conflictRecords,
          <SqlAssignment>[
            conflictRecords.id.set(1),
            conflictRecords.value.set('Returned replacement'),
          ],
          target: <SqlTableColumn<Object?>>[conflictRecords.id],
        )
        .returning(conflictRecords.projection)
        .all(database);
    _expect(returnedConflict.isEmpty, 'ignored conflict returning rows');

    final preservedConflict = await queries
        .selectTable(conflictRecords, where: conflictRecords.id.equals(1))
        .one(database);
    _expect(preservedConflict.id == 1, 'preserved conflict id');
    _expect(preservedConflict.value == 'Original', 'preserved conflict value');

    final insertedMany = await queries
        .insertMany(conflictRecords, <List<SqlAssignment>>[
          <SqlAssignment>[
            conflictRecords.id.set(2),
            conflictRecords.value.set('Second'),
          ],
          <SqlAssignment>[
            conflictRecords.id.set(3),
            conflictRecords.value.set('Third'),
          ],
        ])
        .returning(conflictRecords.projection)
        .all(database);
    _expect(insertedMany.length == 2, 'multi-row returning count');
    // SQL RETURNING does not guarantee input order; ID is the stable key.
    final insertedById = <int, _ConflictRecord>{
      for (final record in insertedMany) record.id: record,
    };
    _expect(insertedById[2]?.value == 'Second', 'multi-row value for ID 2');
    _expect(insertedById[3]?.value == 'Third', 'multi-row value for ID 3');

    final selectedMembership = await queries
        .selectTable(
          conflictRecords,
          where: conflictRecords.id.isIn(<int>[3, 1]),
          orderBy: <SqlOrder>[conflictRecords.id.ascending],
        )
        .all(database);
    _expect(selectedMembership.length == 2, 'membership row count');
    _expect(selectedMembership.first.id == 1, 'membership first ID');
    _expect(selectedMembership.last.id == 3, 'membership last ID');

    await _expectSqlCode(
      () => queries
          .insertMany(conflictRecords, <List<SqlAssignment>>[
            <SqlAssignment>[
              conflictRecords.id.set(4),
              conflictRecords.value.set('Temporary'),
            ],
            <SqlAssignment>[
              conflictRecords.id.set(1),
              conflictRecords.value.set('Duplicate'),
            ],
          ])
          .execute(database),
      SqlErrorCode.constraint,
      'multi-row constraint',
    );
    final afterFailedMany = await queries
        .selectTable(
          conflictRecords,
          orderBy: <SqlOrder>[conflictRecords.id.ascending],
        )
        .all(database);
    _expect(afterFailedMany.length == 3, 'failed multi-row rolled back');
    _expect(afterFailedMany.last.id == 3, 'failed multi-row inserted no tail');

    const name = "Odroe ?'); DROP TABLE records; --";
    final createdAt = DateTime.parse('2026-07-30T12:34:56.789+08:00');
    final inserted = await database.execute(
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
          const SqlValue.text(name),
          const SqlValue.boolean(true),
          SqlValue.time(createdAt),
          SqlValue.blob(Uint8List.fromList(<int>[0, 127, 255])),
        ],
        kind: SqlStatementKind.write,
      ),
    );
    _expect(inserted.affectedRows == 1, 'insert changes');
    _expect(inserted.lastInsertId == 1, 'insert row id');

    final record = (await database.query(
      BoundSql.parts(
        <String>[
          'SELECT id, nullable, count, ratio, name, active, created_at, '
              'payload FROM records WHERE name = ',
          '',
        ],
        const <SqlValue>[SqlValue.text(name)],
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
    _expect(record.read(4, sqlText) == name, 'bound text');
    _expect(record.read(5, sqlBool), 'bound boolean');
    _expect(
      record.read(6, sqlUtcDateTime) ==
          DateTime.parse('2026-07-30T04:34:56.789Z'),
      'UTC timestamp',
    );
    _expect(
      _sameBytes(
        record.read(7, sqlBlob),
        Uint8List.fromList(<int>[0, 127, 255]),
      ),
      'blob bytes',
    );

    final duplicate = (await database.query(
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

    final literal = (await database.query(
      BoundSql.parts(
        <String>["SELECT '?' AS literal, ", ' AS value -- ?'],
        const <SqlValue>[SqlValue.integer(7)],
        kind: SqlStatementKind.rowReturning,
      ),
      (row) => row,
    )).single;
    _expect(literal.read(0, sqlText) == '?', 'literal placeholder');
    _expect(literal.read(1, sqlInt) == 7, 'anonymous placeholder');

    await _expectSqlCode(
      () => database.query(
        BoundSql.parts(
          <String>['INSERT INTO tags (slug) VALUES (', ')'],
          const <SqlValue>[SqlValue.text('unknown-query-must-not-write')],
        ),
        (row) => row,
      ),
      SqlErrorCode.unsupported,
      'query unknown-kind guard',
    );
    await _expectSqlCode(
      () => database.query(
        BoundSql.parts(
          <String>['INSERT INTO tags (slug) VALUES (', ')'],
          const <SqlValue>[SqlValue.text('query-must-not-write')],
          kind: SqlStatementKind.write,
        ),
        (row) => row,
      ),
      SqlErrorCode.unsupported,
      'query write-kind guard',
    );
    await _expectSqlCode(
      () => database.execute(
        BoundSql.parts(
          <String>['INSERT INTO tags (slug) VALUES (', ') RETURNING id'],
          const <SqlValue>[SqlValue.text('execute-must-not-return')],
          kind: SqlStatementKind.rowReturning,
        ),
      ),
      SqlErrorCode.unsupported,
      'execute row-returning guard',
    );
    await _expectSqlCode(
      () => database.atomicWrite(<BoundSql>[
        BoundSql.parts(
          <String>['INSERT INTO tags (slug) VALUES (', ')'],
          const <SqlValue>[SqlValue.text('unknown-must-not-batch')],
        ),
      ]),
      SqlErrorCode.unsupported,
      'batch unknown-kind guard',
    );
    _expect(await _tagCount(database) == 0, 'kind guards ran before SQL');

    final batch = await database.atomicWrite(<BoundSql>[
      _insertTag('one'),
      _insertTag('two'),
    ]);
    _expect(batch.length == 2, 'batch result count');
    _expect(batch[0].affectedRows == 1, 'first batch changes');
    _expect(batch[1].affectedRows == 1, 'second batch changes');
    _expect(batch[0].lastInsertId == 1, 'first batch insert id');
    _expect(batch[1].lastInsertId == 2, 'second batch insert id');

    const secret = 'private@example.com';
    final constraint = await _expectSqlCode(
      () => database.atomicWrite(<BoundSql>[
        _insertTag(secret),
        _insertTag(secret),
      ]),
      SqlErrorCode.constraint,
      'constraint batch',
    );
    _expect(!constraint.message.contains(secret), 'constraint message');
    _expect(!constraint.toString().contains(secret), 'constraint string');
    _expect(constraint.cause == null, 'constraint cause');
    _expect(await _tagCount(database) == 2, 'failed batch rolled back');

    final driver = await _expectSqlCode(
      () => database.execute(
        BoundSql.parts(
          <String>['BROKEN ', ''],
          const <SqlValue>[SqlValue.text(secret)],
        ),
      ),
      SqlErrorCode.driver,
      'driver error',
    );
    _expect(!driver.message.contains(secret), 'driver message');
    _expect(!driver.toString().contains(secret), 'driver string');
    _expect(driver.cause == null, 'driver cause');

    await _expectSqlCode(
      () => database.execute(
        BoundSql.parts(
          <String>['SELECT ', ''],
          const <SqlValue>[SqlValue.integer(9007199254740992)],
        ),
      ),
      SqlErrorCode.invalidValue,
      'unsafe integer',
    );
  } finally {
    await database.close();
  }
}

typedef _ConflictRecord = ({int id, String value});

final class _ConflictRecords extends SqlTable<_ConflictRecord> {
  _ConflictRecords() : super('conflict_records');

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<String> value = column<String>('value', sqlText);

  @override
  late final SqlProjection<_ConflictRecord> projection =
      SqlProjection<_ConflictRecord>(<SqlSelection<Object?>>[
        id,
        value,
      ], (row) => (id: id.read(row, 0), value: value.read(row, 1)));
}

BoundSql _insertTag(String slug) {
  return BoundSql.parts(
    <String>['INSERT INTO tags (slug) VALUES (', ')'],
    <SqlValue>[SqlValue.text(slug)],
    kind: SqlStatementKind.write,
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

Future<SqlException> _expectSqlCode(
  Future<Object?> Function() action,
  SqlErrorCode code,
  String label,
) async {
  try {
    await action();
  } on SqlException catch (error) {
    _expect(error.code == code, label);
    return error;
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

extension type _GlobalThis(JSObject _) implements JSObject {
  external set odroeD1WorkerdTest(JSFunction value);
}

extension type _Environment(JSObject _) implements JSObject {
  @JS('DB')
  external JSObject get database;
}
