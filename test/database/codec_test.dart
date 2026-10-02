import 'dart:typed_data';

import 'package:odroe/database.dart';
import 'package:test/test.dart';

void main() {
  group('scalar codecs', () {
    test('round-trip integers, finite doubles, and text', () {
      expect(sqlInt.decode(sqlInt.encode(7)), 7);
      expect(sqlDouble.decode(sqlDouble.encode(1.5)), 1.5);
      expect(sqlDouble.decode(const SqlValue.integer(2)), 2.0);
      expect(sqlText.decode(sqlText.encode('Odroe')), 'Odroe');
    });

    test('reject non-finite floating-point values', () {
      expect(
        () => SqlValue.real(double.nan),
        _throwsSql(SqlErrorCode.invalidValue),
      );
      expect(
        () => sqlDouble.encode(double.infinity),
        _throwsSql(SqlErrorCode.invalidValue),
      );
    });

    test('decode native and integer booleans', () {
      expect(sqlBool.decode(const SqlValue.boolean(true)), isTrue);
      expect(sqlBool.decode(const SqlValue.integer(0)), isFalse);
      expect(sqlBool.decode(const SqlValue.integer(1)), isTrue);
      expect(
        () => sqlBool.decode(const SqlValue.integer(2)),
        _throwsSql(SqlErrorCode.invalidValue),
      );
    });

    test('preserve binary bytes', () {
      final bytes = Uint8List.fromList(<int>[0, 1, 127, 255]);
      final encoded = sqlBlob.encode(bytes);

      expect(encoded.value, isA<Uint8List>());
      expect(sqlBlob.decode(encoded), orderedEquals(bytes));
    });
  });

  group('UTC timestamp codec', () {
    test('normalizes Dart timestamps to UTC', () {
      final local = DateTime(2026, 7, 30, 12, 34, 56, 789, 123);
      final encoded = sqlUtcDateTime.encode(local);

      expect(encoded.value, local.toUtc());
      expect(sqlUtcDateTime.decode(encoded), local.toUtc());
    });

    test('decodes strings with explicit UTC offsets', () {
      expect(
        sqlUtcDateTime.decode(const SqlValue.text('2026-07-30T12:00:00+08:00')),
        DateTime.utc(2026, 7, 30, 4),
      );
      expect(
        sqlUtcDateTime.decode(const SqlValue.text('2026-07-30T04:00:00Z')),
        DateTime.utc(2026, 7, 30, 4),
      );
    });

    test('rejects timezone-free strings', () {
      expect(
        () => sqlUtcDateTime.decode(const SqlValue.text('2026-07-30T12:00:00')),
        _throwsSql(SqlErrorCode.invalidValue),
      );
    });
  });

  group('nullable codec', () {
    test('makes nullability explicit', () {
      final codec = nullable(sqlText);

      expect(codec.encode(null).isNull, isTrue);
      expect(codec.decode(const SqlValue.nullValue()), isNull);
      expect(codec.decode(const SqlValue.text('value')), 'value');
    });

    test('non-nullable codecs reject NULL', () {
      expect(
        () => sqlText.decode(const SqlValue.nullValue()),
        _throwsSql(SqlErrorCode.invalidValue),
      );
    });
  });
}

Matcher _throwsSql(SqlErrorCode code) =>
    throwsA(isA<SqlException>().having((error) => error.code, 'code', code));
