import 'dart:typed_data';

import 'error.dart';

/// A typed value accepted by SQL statements and row codecs.
///
/// Drivers translate logical booleans and timestamps to their native wire
/// representation. Binary values are not copied and must not be mutated while
/// an operation is in flight.
extension type const SqlValue._(Object? _value) {
  /// Creates SQL `NULL`.
  const SqlValue.nullValue() : this._(null);

  /// Creates an integer value.
  const SqlValue.integer(int value) : this._(value);

  /// Creates a finite floating-point value.
  factory SqlValue.real(double value) {
    if (!value.isFinite) {
      throw SqlException(
        SqlErrorCode.invalidValue,
        'SQL floating-point values must be finite.',
      );
    }
    return SqlValue._(value);
  }

  /// Creates a text value.
  const SqlValue.text(String value) : this._(value);

  /// Creates a logical boolean value.
  const SqlValue.boolean(bool value) : this._(value);

  /// Creates a timestamp normalized to UTC.
  factory SqlValue.time(DateTime value) => SqlValue._(value.toUtc());

  /// Creates a binary value without copying [value].
  const SqlValue.blob(Uint8List value) : this._(value);

  /// The normalized logical value used by drivers and custom codecs.
  Object? get value => _value;

  /// Whether this value represents SQL `NULL`.
  bool get isNull => _value == null;
}

/// Converts one Dart type to and from [SqlValue].
abstract interface class SqlCodec<T> {
  /// Encodes [value] for a bound SQL parameter.
  SqlValue encode(T value);

  /// Decodes one normalized SQL [value].
  T decode(SqlValue value);
}

/// Codec for SQL integer values.
const SqlCodec<int> sqlInt = _SqlCodec<int>(_encodeInt, _decodeInt);

/// Codec for finite SQL floating-point values.
///
/// Integer rows are widened to [double].
const SqlCodec<double> sqlDouble = _SqlCodec<double>(
  _encodeDouble,
  _decodeDouble,
);

/// Codec for SQL text values.
const SqlCodec<String> sqlText = _SqlCodec<String>(_encodeText, _decodeText);

/// Codec for logical SQL booleans.
///
/// Decoding accepts native booleans and SQLite-compatible integers `0` and
/// `1`.
const SqlCodec<bool> sqlBool = _SqlCodec<bool>(_encodeBool, _decodeBool);

/// Codec for SQL binary values.
const SqlCodec<Uint8List> sqlBlob = _SqlCodec<Uint8List>(
  _encodeBlob,
  _decodeBlob,
);

/// Codec for SQL timestamps normalized to UTC.
///
/// Decoding accepts a [DateTime] or an ISO-8601 string containing an explicit
/// UTC offset.
const SqlCodec<DateTime> sqlUtcDateTime = _SqlCodec<DateTime>(
  _encodeUtcDateTime,
  _decodeUtcDateTime,
);

/// Makes [codec] explicitly nullable.
SqlCodec<T?> nullable<T>(SqlCodec<T> codec) => _NullableSqlCodec<T>(codec);

final class _SqlCodec<T> implements SqlCodec<T> {
  const _SqlCodec(this._encode, this._decode);

  final SqlValue Function(T value) _encode;
  final T Function(SqlValue value) _decode;

  @override
  SqlValue encode(T value) => _encode(value);

  @override
  T decode(SqlValue value) => _decode(value);
}

final class _NullableSqlCodec<T> implements SqlCodec<T?> {
  const _NullableSqlCodec(this._codec);

  final SqlCodec<T> _codec;

  @override
  SqlValue encode(T? value) =>
      value == null ? const SqlValue.nullValue() : _codec.encode(value);

  @override
  T? decode(SqlValue value) => value.isNull ? null : _codec.decode(value);
}

SqlValue _encodeInt(int value) => SqlValue.integer(value);

int _decodeInt(SqlValue value) {
  final raw = value.value;
  if (raw is int) return raw;
  throw _typeError('an integer', raw);
}

SqlValue _encodeDouble(double value) => SqlValue.real(value);

double _decodeDouble(SqlValue value) {
  final raw = value.value;
  if (raw is int) return raw.toDouble();
  if (raw is double && raw.isFinite) return raw;
  throw _typeError('a finite number', raw);
}

SqlValue _encodeText(String value) => SqlValue.text(value);

String _decodeText(SqlValue value) {
  final raw = value.value;
  if (raw is String) return raw;
  throw _typeError('text', raw);
}

SqlValue _encodeBool(bool value) => SqlValue.boolean(value);

bool _decodeBool(SqlValue value) {
  return switch (value.value) {
    final bool value => value,
    0 => false,
    1 => true,
    final Object? value => throw _typeError(
      'a boolean or the integer 0 or 1',
      value,
    ),
  };
}

SqlValue _encodeBlob(Uint8List value) => SqlValue.blob(value);

Uint8List _decodeBlob(SqlValue value) {
  final raw = value.value;
  if (raw is Uint8List) return raw;
  throw _typeError('binary data', raw);
}

SqlValue _encodeUtcDateTime(DateTime value) => SqlValue.time(value);

DateTime _decodeUtcDateTime(SqlValue value) {
  final raw = value.value;
  if (raw is DateTime) return raw.toUtc();
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null && parsed.isUtc) return parsed.toUtc();
  }
  throw _typeError('an ISO-8601 timestamp with a UTC offset', raw);
}

SqlException _typeError(String expected, Object? actual) => SqlException(
  SqlErrorCode.invalidValue,
  'Expected $expected, received ${_valueKind(actual)}.',
);

String _valueKind(Object? value) => switch (value) {
  null => 'NULL',
  int() => 'an integer',
  double() => 'a floating-point value',
  String() => 'text',
  bool() => 'a boolean',
  DateTime() => 'a timestamp',
  Uint8List() => 'binary data',
  _ => value.runtimeType.toString(),
};
