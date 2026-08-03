import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:odroe/database_mysql.dart';
import 'package:test/test.dart';

import 'pool_contract.dart';

void main() {
  final config = _MysqlTestConfig.fromEnvironment();
  final skipReason = config == null
      ? 'Set ODROE_MYSQL_HOST, ODROE_MYSQL_DATABASE, and '
            'ODROE_MYSQL_USERNAME to run real MySQL/MariaDB contract tests.'
      : false;
  final suffix = '${pid}_${DateTime.now().microsecondsSinceEpoch}';

  group('MysqlDatabase real contract', () {
    late MysqlDatabase database;
    final tables = <String>[];

    setUp(() async {
      database = await config!.open();
    });

    tearDown(() async {
      for (final table in tables.reversed) {
        try {
          await database.execute(BoundSql.raw('DROP TABLE IF EXISTS `$table`'));
        } on Object {
          // Keep cleanup best-effort so the original test failure is visible.
        }
      }
      tables.clear();
      await database.close();
    });

    test('runs real CRUD with portable values and ordered rows', () async {
      final table = 'odroe_mysql_records_$suffix';
      tables.add(table);
      await database.execute(
        BoundSql.raw('''
          CREATE TABLE `$table` (
            id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            name TEXT NOT NULL,
            active BOOLEAN NOT NULL,
            created_at DATETIME(6) NOT NULL,
            payload BLOB NOT NULL,
            quantity BIGINT NOT NULL,
            score DOUBLE NOT NULL,
            optional_text TEXT NULL,
            UNIQUE KEY `${table}_name_unique` (name(191))
          )
        '''),
      );

      final createdAt = DateTime.parse(
        '2026-07-30T12:05:06.007008+08:00',
      ).toUtc();
      final payload = Uint8List.fromList(<int>[0, 1, 127, 255]);
      final inserted = await database.execute(
        BoundSql.parts(
          <String>[
            'INSERT INTO `$table` '
                '(name, active, created_at, payload, quantity, score, '
                'optional_text) VALUES (',
            ', ',
            ', ',
            ', ',
            ', ',
            ', ',
            ', ',
            ')',
          ],
          <SqlValue>[
            const SqlValue.text('Odroe'),
            const SqlValue.boolean(true),
            SqlValue.time(createdAt),
            SqlValue.blob(payload),
            const SqlValue.integer(42),
            SqlValue.real(3.5),
            const SqlValue.nullValue(),
          ],
        ),
      );
      expect(inserted.affectedRows, 1);
      expect(inserted.lastInsertId, 1);

      final row = (await database.query(
        BoundSql.parts(
          <String>[
            'SELECT id, name, active, created_at, payload, quantity, score, '
                'optional_text FROM `$table` WHERE name = ',
            '',
          ],
          <SqlValue>[const SqlValue.text('Odroe')],
        ),
        (row) => row,
      )).single;
      expect(
        <String>[
          for (var index = 0; index < row.length; index++) row.nameAt(index),
        ],
        <String>[
          'id',
          'name',
          'active',
          'created_at',
          'payload',
          'quantity',
          'score',
          'optional_text',
        ],
      );
      expect(row.read(0, sqlInt), 1);
      expect(row.read(1, sqlText), 'Odroe');
      expect(row.read(2, sqlBool), isTrue);
      expect(row.read(3, sqlUtcDateTime), createdAt);
      expect(row.read(4, sqlBlob), orderedEquals(payload));
      expect(row.read(5, sqlInt), 42);
      expect(row.read(6, sqlDouble), 3.5);
      expect(row.read(7, nullable(sqlText)), isNull);

      final duplicateLabels = (await database.query(
        BoundSql.raw('SELECT 1 AS id, 2 AS id, 3 AS value'),
        (row) => row,
      )).single;
      expect(
        <String>[
          duplicateLabels.nameAt(0),
          duplicateLabels.nameAt(1),
          duplicateLabels.nameAt(2),
        ],
        <String>['id', 'id', 'value'],
      );
      expect(duplicateLabels.read(0, sqlInt), 1);
      expect(duplicateLabels.read(1, sqlInt), 2);
      expect(duplicateLabels.read(2, sqlInt), 3);

      final placeholderText = await database.query(
        BoundSql.parts(
          <String>[r"SELECT '?' AS literal, ", r' AS value /* ? */'],
          <SqlValue>[const SqlValue.integer(7)],
        ),
        (row) => (row.read(0, sqlText), row.read(1, sqlInt)),
      );
      expect(placeholderText.single, ('?', 7));

      await expectLater(
        database.execute(BoundSql.raw('SELECT 1')),
        _throwsSql(SqlErrorCode.unsupported),
      );
    });

    test('runs one atomic typed multi-row INSERT', () async {
      final table = 'odroe_mysql_many_$suffix';
      final linksTable = 'odroe_mysql_many_links_$suffix';
      tables.add(table);
      tables.add(linksTable);
      await database.execute(
        BoundSql.raw('''
          CREATE TABLE `$table` (
            id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            label VARCHAR(191) NOT NULL UNIQUE,
            counter BIGINT NOT NULL DEFAULT 0
          )
        '''),
      );
      await database.execute(
        BoundSql.raw('''
          CREATE TABLE `$linksTable` (
            record_id BIGINT NOT NULL
          )
        '''),
      );
      final records = _MysqlBatchRecords(table);
      final links = _MysqlBatchLinks(linksTable);
      const queries = SqlQueries(SqlDialect.mysql);

      final inserted = await queries
          .insertMany(records, <List<SqlAssignment>>[
            <SqlAssignment>[records.label.set('First')],
            <SqlAssignment>[records.label.set('Second')],
          ])
          .execute(database);
      expect(inserted.affectedRows, 2);
      final incremented = await queries
          .updateWhere(records, <SqlUpdateAssignment>[
            records.counter.incrementBy(4),
          ], where: records.id.equals(2))
          .execute(database);
      expect(incremented.affectedRows, 1);
      expect(
        await queries
            .select(
              from: records,
              projection: SqlProjection.column(records.counter),
              where: records.id.equals(2),
            )
            .one(database),
        4,
      );
      expect(
        await queries
            .selectTable(
              records,
              where: records.id.isIn(<int>[2, 1]),
              orderBy: <SqlOrder>[records.id.ascending],
            )
            .all(database),
        <_MysqlBatchRecord>[(id: 1, label: 'First'), (id: 2, label: 'Second')],
      );
      expect(await queries.countRows(records).one(database), 2);
      expect(
        await queries
            .countRows(records, where: records.label.equals('Second'))
            .one(database),
        1,
      );
      await queries
          .insertMany(links, <List<SqlAssignment>>[
            <SqlAssignment>[links.recordId.set(1)],
            <SqlAssignment>[links.recordId.set(1)],
          ])
          .execute(database);
      expect(
        await queries
            .countRows(
              records,
              joins: <SqlJoin>[
                SqlJoin.left(
                  links,
                  on: records.id.equalsColumn(links.recordId),
                ),
              ],
            )
            .one(database),
        3,
      );

      await expectLater(
        queries
            .insertMany(records, <List<SqlAssignment>>[
              <SqlAssignment>[records.label.set('Temporary')],
              <SqlAssignment>[records.label.set('First')],
            ])
            .execute(database),
        _throwsSql(SqlErrorCode.constraint),
      );
      expect(await queries.countRows(records).one(database), 2);
    });

    test('rolls back atomic and interactive transaction failures', () async {
      final table = 'odroe_mysql_transactions_$suffix';
      tables.add(table);
      await database.execute(
        BoundSql.raw('''
          CREATE TABLE `$table` (
            id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            label VARCHAR(191) NOT NULL UNIQUE
          )
        '''),
      );

      await expectLater(
        database.atomicWrite(<BoundSql>[
          _insert(table, 'duplicate'),
          _insert(table, 'duplicate'),
        ]),
        _throwsSql(SqlErrorCode.constraint),
      );
      expect(await _count(database, table), 0);

      await expectLater(
        database.transaction<void>((transaction) async {
          expect(transaction, isNot(isA<SqlDatabase>()));
          await transaction.execute(_insert(table, 'temporary'));
          final count = await transaction.query(
            BoundSql.raw(
              'SELECT COUNT(*) FROM `$table`',
              kind: SqlStatementKind.rowReturning,
            ),
            (row) => row.read(0, sqlInt),
          );
          expect(count, <int>[1]);
          await expectLater(
            database.execute(_insert(table, 'parent')),
            _throwsSql(SqlErrorCode.unsupported),
          );
          await expectLater(
            database.transaction<void>((_) async {}),
            _throwsSql(SqlErrorCode.unsupported),
          );
          throw StateError('abort');
        }),
        throwsStateError,
      );
      expect(await _count(database, table), 0);

      late SqlExecutor escaped;
      await database.transaction<void>((transaction) async {
        escaped = transaction;
        await transaction.execute(_insert(table, 'committed'));
      });
      await expectLater(
        escaped.execute(_insert(table, 'escaped')),
        _throwsSql(SqlErrorCode.closed),
      );
      expect(await _count(database, table), 1);
    });

    test('rejects unmarked transaction control before sending it', () async {
      final table = 'odroe_mysql_guarded_$suffix';
      tables.add(table);
      await database.execute(
        BoundSql.raw('CREATE TABLE `$table` (value BIGINT NOT NULL)'),
      );

      await expectLater(
        database.transaction<void>((transaction) async {
          await transaction.execute(
            BoundSql.raw(
              'INSERT INTO `$table` VALUES (1)',
              kind: SqlStatementKind.write,
            ),
          );
          await expectLater(
            transaction.execute(BoundSql.raw('COMMIT')),
            _throwsSql(SqlErrorCode.unsupported),
          );
          throw StateError('abort after rejected COMMIT');
        }),
        throwsStateError,
      );
      await expectLater(
        database.transaction<void>((transaction) async {
          await transaction.execute(
            BoundSql.raw(
              'INSERT INTO `$table` VALUES (2)',
              kind: SqlStatementKind.write,
            ),
          );
          await expectLater(
            transaction.query(BoundSql.raw('ROLLBACK'), (row) => row),
            _throwsSql(SqlErrorCode.unsupported),
          );
          throw StateError('abort after rejected ROLLBACK');
        }),
        throwsStateError,
      );

      expect(await _count(database, table), 0);
    });

    test('rejects explicit opposite kinds before execution', () async {
      final table = 'odroe_mysql_shaped_$suffix';
      tables.add(table);
      await database.execute(
        BoundSql.raw('CREATE TABLE `$table` (value BIGINT NOT NULL)'),
      );

      await expectLater(
        database.query(
          BoundSql.raw(
            'INSERT INTO `$table` VALUES (1)',
            kind: SqlStatementKind.write,
          ),
          (row) => row,
        ),
        _throwsSql(SqlErrorCode.unsupported),
      );
      await expectLater(
        database.execute(
          BoundSql.raw(
            'SELECT value FROM `$table`',
            kind: SqlStatementKind.rowReturning,
          ),
        ),
        _throwsSql(SqlErrorCode.unsupported),
      );
      await expectLater(
        database.atomicWrite(<BoundSql>[
          BoundSql.raw('INSERT INTO `$table` VALUES (2)'),
        ]),
        _throwsSql(SqlErrorCode.unsupported),
      );

      expect(await _count(database, table), 0);
    });

    test('rejects mismatched dialects at every executor boundary', () async {
      await expectLater(
        database.query(
          BoundSql.raw(
            _dialectSentinel,
            kind: SqlStatementKind.rowReturning,
            dialect: SqlDialect.postgres,
          ),
          (row) => row,
        ),
        _throwsDialect('MySQL', SqlDialect.postgres),
      );
      await expectLater(
        database.execute(
          BoundSql.raw(
            _dialectSentinel,
            kind: SqlStatementKind.write,
            dialect: SqlDialect.sqlite,
          ),
        ),
        _throwsDialect('MySQL', SqlDialect.sqlite),
      );
      await expectLater(
        database.atomicWrite(<BoundSql>[
          BoundSql.raw(
            _dialectSentinel,
            kind: SqlStatementKind.write,
            dialect: SqlDialect.mysql,
          ),
          BoundSql.raw(
            _dialectSentinel,
            kind: SqlStatementKind.write,
            dialect: SqlDialect.postgres,
          ),
        ]),
        _throwsDialect('MySQL', SqlDialect.postgres),
      );

      final table = 'odroe_mysql_dialect_$suffix';
      tables.add(table);
      await database.execute(
        BoundSql.raw('CREATE TABLE `$table` (value BIGINT NOT NULL)'),
      );
      await database.transaction<void>((transaction) async {
        await expectLater(
          transaction.query(
            BoundSql.raw(
              _dialectSentinel,
              kind: SqlStatementKind.rowReturning,
              dialect: SqlDialect.postgres,
            ),
            (row) => row,
          ),
          _throwsDialect('MySQL', SqlDialect.postgres),
        );
        await expectLater(
          transaction.execute(
            BoundSql.raw(
              _dialectSentinel,
              kind: SqlStatementKind.write,
              dialect: SqlDialect.sqlite,
            ),
          ),
          _throwsDialect('MySQL', SqlDialect.sqlite),
        );
        await transaction.execute(
          BoundSql.raw(
            'INSERT INTO `$table` VALUES (1)',
            kind: SqlStatementKind.write,
            dialect: SqlDialect.mysql,
          ),
        );
      });

      expect(await _count(database, table), 1);
    });

    test('rejects compound SQL before any statement runs', () async {
      final table = 'odroe_mysql_compound_$suffix';
      tables.add(table);
      await database.execute(
        BoundSql.raw('CREATE TABLE `$table` (value VARCHAR(191) NOT NULL)'),
      );

      await expectLater(
        database.execute(
          BoundSql.raw(
            "INSERT INTO `$table` VALUES ('one'); "
            "INSERT INTO `$table` VALUES ('two')",
          ),
        ),
        _throwsSql(SqlErrorCode.unsupported),
      );
      expect(await _count(database, table), 0);

      await expectLater(
        database.execute(
          BoundSql.parts(
            <String>[
              'INSERT INTO `$table` VALUES (',
              "); INSERT INTO `$table` VALUES ('two')",
            ],
            <SqlValue>[const SqlValue.text('one')],
          ),
        ),
        _throwsSql(SqlErrorCode.driver),
      );
      expect(await _count(database, table), 0);
    });

    test('serializes external work and closes idempotently', () async {
      final table = 'odroe_mysql_serial_$suffix';
      tables.add(table);
      await database.execute(
        BoundSql.raw('''
          CREATE TABLE `$table` (
            id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            label VARCHAR(191) NOT NULL
          )
        '''),
      );
      final entered = Completer<void>();
      final release = Completer<void>();

      final transaction = database.transaction<void>((transaction) async {
        await transaction.execute(_insert(table, 'inside-1'));
        entered.complete();
        await release.future;
        await transaction.execute(_insert(table, 'inside-2'));
      });
      await entered.future;

      var externalCompleted = false;
      final external = database.execute(_insert(table, 'outside')).then((
        result,
      ) {
        externalCompleted = true;
        return result;
      });
      await Future<void>.delayed(Duration.zero);
      expect(externalCompleted, isFalse);

      release.complete();
      await transaction;
      await external;

      final labels = await database.query(
        BoundSql.raw('SELECT label FROM `$table` ORDER BY id'),
        (row) => row.read(0, sqlText),
      );
      expect(labels, <String>['inside-1', 'inside-2', 'outside']);

      await database.execute(BoundSql.raw('DROP TABLE `$table`'));
      tables.remove(table);
      final firstClose = database.close();
      final secondClose = database.close();
      expect(identical(firstClose, secondClose), isTrue);
      await firstClose;
      await expectLater(
        database.query(BoundSql.raw('SELECT 1'), (row) => row),
        _throwsSql(SqlErrorCode.closed),
      );
    });
  }, skip: skipReason);

  group('MysqlDatabase real pool contract', () {
    defineMysqlPoolContract(
      ({
        int? maxConnections,
        int? maxPendingOperations,
        Duration? queueTimeout,
      }) => config!.pool(
        maxConnections: maxConnections ?? 4,
        maxPendingOperations: maxPendingOperations ?? 32,
        queueTimeout: queueTimeout ?? const Duration(seconds: 10),
      ),
      () => config!.open(),
    );
  }, skip: skipReason);
}

typedef _MysqlBatchRecord = ({int id, String label});

final class _MysqlBatchRecords extends SqlTable<_MysqlBatchRecord> {
  _MysqlBatchRecords(super.name);

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<String> label = column<String>('label', sqlText);
  late final SqlTableColumn<int> counter = column<int>('counter', sqlInt);

  @override
  late final SqlProjection<_MysqlBatchRecord> projection =
      SqlProjection<_MysqlBatchRecord>(<SqlSelection<Object?>>[
        id,
        label,
      ], (row) => (id: id.read(row, 0), label: label.read(row, 1)));
}

final class _MysqlBatchLinks extends SqlTable<int> {
  _MysqlBatchLinks(super.name);

  late final SqlTableColumn<int> recordId = column<int>('record_id', sqlInt);

  @override
  late final SqlProjection<int> projection = SqlProjection.column(recordId);
}

final class _MysqlTestConfig {
  const _MysqlTestConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    required this.useTls,
    required this.allowPublicKeyRetrieval,
  });

  static _MysqlTestConfig? fromEnvironment() {
    final environment = Platform.environment;
    final host = environment['ODROE_MYSQL_HOST'];
    final database = environment['ODROE_MYSQL_DATABASE'];
    final username = environment['ODROE_MYSQL_USERNAME'];
    if (host == null || database == null || username == null) {
      return null;
    }
    final port = int.tryParse(environment['ODROE_MYSQL_PORT'] ?? '3306');
    if (port == null) {
      throw const FormatException('ODROE_MYSQL_PORT must be an integer.');
    }
    return _MysqlTestConfig(
      host: host,
      port: port,
      database: database,
      username: username,
      password: environment['ODROE_MYSQL_PASSWORD'] ?? '',
      useTls: environment['ODROE_MYSQL_TLS'] == 'true',
      allowPublicKeyRetrieval:
          environment['ODROE_MYSQL_ALLOW_PUBLIC_KEY_RETRIEVAL'] == 'true',
    );
  }

  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final bool useTls;
  final bool allowPublicKeyRetrieval;

  Future<MysqlDatabase> open() {
    return MysqlDatabase.open(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      useTls: useTls,
      allowPublicKeyRetrieval: allowPublicKeyRetrieval,
    );
  }

  MysqlDatabase pool({
    int maxConnections = 4,
    int maxPendingOperations = 32,
    Duration queueTimeout = const Duration(seconds: 10),
  }) {
    return MysqlDatabase.pool(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      maxConnections: maxConnections,
      maxPendingOperations: maxPendingOperations,
      queueTimeout: queueTimeout,
      useTls: useTls,
      allowPublicKeyRetrieval: allowPublicKeyRetrieval,
    );
  }
}

BoundSql _insert(String table, String label) {
  return BoundSql.parts(
    <String>['INSERT INTO `$table` (label) VALUES (', ')'],
    <SqlValue>[SqlValue.text(label)],
    kind: SqlStatementKind.write,
  );
}

Future<int> _count(MysqlDatabase database, String table) async {
  return (await database.query(
    BoundSql.raw('SELECT COUNT(*) FROM `$table`'),
    (row) => row.read(0, sqlInt),
  )).single;
}

Matcher _throwsSql(SqlErrorCode code) {
  return throwsA(
    isA<SqlException>().having((error) => error.code, 'code', code),
  );
}

Matcher _throwsDialect(String database, SqlDialect actual) {
  return throwsA(
    isA<SqlException>()
        .having((error) => error.code, 'code', SqlErrorCode.unsupported)
        .having((error) => error.message, 'message', contains(database))
        .having((error) => error.message, 'message', contains(actual.name))
        .having(
          (error) => error.message,
          'message',
          isNot(contains(_dialectSentinel)),
        ),
  );
}

const _dialectSentinel = 'DIALECT_SENTINEL private-value';
