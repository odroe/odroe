import 'package:odroe/database.dart';

const _iterations = 500000;
const _warmups = 3;
const _samples = 9;

void main() {
  final records = _BenchmarkRecords();
  final row = SqlRow(
    <String>['id', 'label'],
    <SqlValue>[const SqlValue.integer(42), const SqlValue.text('Odroe')],
  );

  int decodePositionally() {
    var checksum = 0;
    for (var index = 0; index < _iterations; index++) {
      final record = (
        id: records.id.read(row, 0),
        label: records.label.read(row, 1),
      );
      checksum += record.id + record.label.length;
    }
    return checksum;
  }

  int decodeProjection() {
    var checksum = 0;
    for (var index = 0; index < _iterations; index++) {
      final record = records.projection.decode(row);
      checksum += record.id + record.label.length;
    }
    return checksum;
  }

  _compare(
    '2-column projection',
    positional: decodePositionally,
    projection: decodeProjection,
    expectedChecksum: _iterations * 47,
  );

  final wideRecords = _WideBenchmarkRecords();
  final wideRow = SqlRow(
    <String>['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
    <SqlValue>[
      for (var value = 1; value <= 8; value++) SqlValue.integer(value),
    ],
  );

  int decodeWidePositionally() {
    var checksum = 0;
    for (var index = 0; index < _iterations; index++) {
      final record = (
        a: wideRecords.a.read(wideRow, 0),
        b: wideRecords.b.read(wideRow, 1),
        c: wideRecords.c.read(wideRow, 2),
        d: wideRecords.d.read(wideRow, 3),
        e: wideRecords.e.read(wideRow, 4),
        f: wideRecords.f.read(wideRow, 5),
        g: wideRecords.g.read(wideRow, 6),
        h: wideRecords.h.read(wideRow, 7),
      );
      checksum +=
          record.a +
          record.b +
          record.c +
          record.d +
          record.e +
          record.f +
          record.g +
          record.h;
    }
    return checksum;
  }

  int decodeWideProjection() {
    var checksum = 0;
    for (var index = 0; index < _iterations; index++) {
      final record = wideRecords.projection.decode(wideRow);
      checksum +=
          record.a +
          record.b +
          record.c +
          record.d +
          record.e +
          record.f +
          record.g +
          record.h;
    }
    return checksum;
  }

  _compare(
    '8-column projection',
    positional: decodeWidePositionally,
    projection: decodeWideProjection,
    expectedChecksum: _iterations * 36,
  );
}

void _compare(
  String label, {
  required int Function() positional,
  required int Function() projection,
  required int expectedChecksum,
}) {
  for (var index = 0; index < _warmups; index++) {
    _verify(positional(), expectedChecksum);
    _verify(projection(), expectedChecksum);
  }

  final positionalTimes = <Duration>[];
  final projectionTimes = <Duration>[];
  for (var index = 0; index < _samples; index++) {
    if (index.isEven) {
      positionalTimes.add(_measure(positional, expectedChecksum));
      projectionTimes.add(_measure(projection, expectedChecksum));
    } else {
      projectionTimes.add(_measure(projection, expectedChecksum));
      positionalTimes.add(_measure(positional, expectedChecksum));
    }
  }

  final positionalMedian = _median(positionalTimes);
  final projectionMedian = _median(projectionTimes);
  print(label);
  _printResult('positional selection reads', positionalMedian);
  _printResult('selection-addressed projection', projectionMedian);
  final overhead =
      (projectionMedian.inMicroseconds - positionalMedian.inMicroseconds) /
      positionalMedian.inMicroseconds *
      100;
  print('projection overhead: ${overhead.toStringAsFixed(1)}%');
}

Duration _measure(int Function() decode, int expectedChecksum) {
  final stopwatch = Stopwatch()..start();
  final checksum = decode();
  stopwatch.stop();
  _verify(checksum, expectedChecksum);
  return stopwatch.elapsed;
}

void _verify(int actual, int expected) {
  if (actual != expected) {
    throw StateError('Expected checksum $expected, received $actual.');
  }
}

Duration _median(List<Duration> values) {
  final sorted = List<Duration>.of(values)
    ..sort((left, right) => left.compareTo(right));
  return sorted[sorted.length ~/ 2];
}

void _printResult(String name, Duration median) {
  final nanosecondsPerRow = median.inMicroseconds * 1000 / _iterations;
  print(
    '$name: ${nanosecondsPerRow.toStringAsFixed(1)} ns/row '
    '($_iterations rows, $_samples samples)',
  );
}

typedef _BenchmarkRecord = ({int id, String label});

final class _BenchmarkRecords extends SqlTable<_BenchmarkRecord> {
  _BenchmarkRecords() : super('benchmark_records');

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<String> label = column<String>('label', sqlText);

  @override
  late final SqlProjection<_BenchmarkRecord> projection =
      SqlProjection<_BenchmarkRecord>(
        columns: [id, label],
        decode: (row) => (id: row.read(id), label: row.read(label)),
      );
}

typedef _WideBenchmarkRecord = ({
  int a,
  int b,
  int c,
  int d,
  int e,
  int f,
  int g,
  int h,
});

final class _WideBenchmarkRecords extends SqlTable<_WideBenchmarkRecord> {
  _WideBenchmarkRecords() : super('wide_benchmark_records');

  late final SqlTableColumn<int> a = column<int>('a', sqlInt);
  late final SqlTableColumn<int> b = column<int>('b', sqlInt);
  late final SqlTableColumn<int> c = column<int>('c', sqlInt);
  late final SqlTableColumn<int> d = column<int>('d', sqlInt);
  late final SqlTableColumn<int> e = column<int>('e', sqlInt);
  late final SqlTableColumn<int> f = column<int>('f', sqlInt);
  late final SqlTableColumn<int> g = column<int>('g', sqlInt);
  late final SqlTableColumn<int> h = column<int>('h', sqlInt);

  @override
  late final SqlProjection<_WideBenchmarkRecord> projection =
      SqlProjection<_WideBenchmarkRecord>(
        columns: [a, b, c, d, e, f, g, h],
        decode: (row) => (
          a: row.read(a),
          b: row.read(b),
          c: row.read(c),
          d: row.read(d),
          e: row.read(e),
          f: row.read(f),
          g: row.read(g),
          h: row.read(h),
        ),
      );
}
