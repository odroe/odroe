import 'package:odroe/database_sqlite.dart';

const _rowCount = 1000;
const _warmups = 2;
const _samples = 9;

Future<void> main() async {
  final database = SqliteDatabase.openInMemory();
  final records = _BenchmarkRecords();
  const queries = SqlQueries(SqlDialect.sqlite);
  try {
    await database.execute(
      BoundSql.raw(
        'CREATE TABLE benchmark_records (value TEXT NOT NULL) STRICT',
        dialect: SqlDialect.sqlite,
      ),
    );

    final rows = <List<SqlAssignment>>[
      for (var index = 0; index < _rowCount; index++)
        <SqlAssignment>[records.value.set('row-$index')],
    ];
    final singleStatements = <BoundSql>[
      for (final row in rows) queries.insert(records, row).statement,
    ];
    final insertMany = queries.insertMany(records, rows);

    Future<Duration> runAtomicWrite() async {
      await _clear(database, queries, records);
      final stopwatch = Stopwatch()..start();
      final results = await database.atomicWrite(singleStatements);
      stopwatch.stop();
      if (results.length != _rowCount) {
        throw StateError('atomicWrite returned ${results.length} results.');
      }
      await _verifyCount(database, _rowCount);
      return stopwatch.elapsed;
    }

    Future<Duration> runInsertMany() async {
      await _clear(database, queries, records);
      final stopwatch = Stopwatch()..start();
      final result = await insertMany.execute(database);
      stopwatch.stop();
      if (result.affectedRows != _rowCount) {
        throw StateError('insertMany changed ${result.affectedRows} rows.');
      }
      await _verifyCount(database, _rowCount);
      return stopwatch.elapsed;
    }

    for (var index = 0; index < _warmups; index++) {
      await runAtomicWrite();
      await runInsertMany();
    }

    final atomicTimes = <Duration>[];
    final manyTimes = <Duration>[];
    for (var index = 0; index < _samples; index++) {
      if (index.isEven) {
        atomicTimes.add(await runAtomicWrite());
        manyTimes.add(await runInsertMany());
      } else {
        manyTimes.add(await runInsertMany());
        atomicTimes.add(await runAtomicWrite());
      }
    }

    _printResult(
      'atomicWrite(single INSERTs)',
      statements: singleStatements.length,
      median: _median(atomicTimes),
    );
    _printResult('insertMany', statements: 1, median: _median(manyTimes));
  } finally {
    await database.close();
  }
}

Future<void> _clear(
  SqliteDatabase database,
  SqlQueries queries,
  _BenchmarkRecords records,
) async {
  await queries.deleteAll(records, confirm: allRows).execute(database);
}

Future<void> _verifyCount(SqliteDatabase database, int expected) async {
  final count = (await database.query(
    BoundSql.raw(
      'SELECT count(*) AS count FROM benchmark_records',
      kind: SqlStatementKind.rowReturning,
      dialect: SqlDialect.sqlite,
    ),
    (row) => row.read(0, sqlInt),
  )).single;
  if (count != expected) {
    throw StateError('Expected $expected rows, found $count.');
  }
}

Duration _median(List<Duration> values) {
  final sorted = List<Duration>.of(values)
    ..sort((left, right) => left.compareTo(right));
  return sorted[sorted.length ~/ 2];
}

void _printResult(
  String name, {
  required int statements,
  required Duration median,
}) {
  final milliseconds = median.inMicroseconds / 1000;
  print(
    '$name: $statements statement${statements == 1 ? '' : 's'}, '
    'median ${milliseconds.toStringAsFixed(2)} ms '
    '($_rowCount rows, $_samples samples)',
  );
}

final class _BenchmarkRecords extends SqlTable<String> {
  _BenchmarkRecords() : super('benchmark_records');

  late final SqlTableColumn<String> value = column<String>('value', sqlText);

  @override
  late final SqlProjection<String> projection = SqlProjection.column(value);
}
