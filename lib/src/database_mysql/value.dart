import 'dart:typed_data';

import 'package:mysql_dart/mysql_client.dart' as mysql;
import 'package:mysql_dart/mysql_protocol.dart' as protocol;

import '../database/codec.dart';
import '../database/error.dart';
import '../database/result.dart';

/// Converts one `mysql_dart` result value to Odroe's portable value domain.
SqlValue readMysqlValue(
  mysql.ResultSetColumn column,
  Object? raw, {
  required bool binary,
}) {
  if (raw == null) return const SqlValue.nullValue();

  return switch (column.type.intVal) {
    protocol.mysqlColumnTypeTiny ||
    protocol.mysqlColumnTypeShort ||
    protocol.mysqlColumnTypeLong ||
    protocol.mysqlColumnTypeLongLong ||
    protocol.mysqlColumnTypeInt24 ||
    protocol.mysqlColumnTypeYear => _readInteger(raw),
    protocol.mysqlColumnTypeFloat ||
    protocol.mysqlColumnTypeDouble => _readDouble(raw),
    protocol.mysqlColumnTypeDate ||
    protocol.mysqlColumnTypeNewDate ||
    protocol.mysqlColumnTypeDateTime ||
    protocol.mysqlColumnTypeDateTime2 ||
    protocol.mysqlColumnTypeTimestamp ||
    protocol.mysqlColumnTypeTimestamp2 => _readTimestamp(raw, binary: binary),
    protocol.mysqlColumnTypeTime ||
    protocol.mysqlColumnTypeTime2 => throw const SqlException(
      SqlErrorCode.invalidRow,
      'MySQL TIME values are outside the portable timestamp domain.',
    ),
    _ => _readScalar(raw),
  };
}

/// Converts MySQL write counters without truncating `BigInt`.
SqlWriteResult mysqlWriteResult(BigInt affectedRows, BigInt lastInsertId) {
  final affected = _checkedNonNegativeInt(affectedRows, 'affected rows');
  final id = lastInsertId == BigInt.zero
      ? null
      : _checkedNonNegativeInt(lastInsertId, 'last insert ID');
  return SqlWriteResult(affectedRows: affected, lastInsertId: id);
}

SqlValue _readInteger(Object raw) {
  final value = switch (raw) {
    final int value => value,
    final String value => int.tryParse(value),
    _ => null,
  };
  if (value == null) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'MySQL returned an invalid signed integer.',
    );
  }
  return SqlValue.integer(value);
}

SqlValue _readDouble(Object raw) {
  final value = switch (raw) {
    final double value => value,
    final int value => value.toDouble(),
    final String value => double.tryParse(value),
    _ => null,
  };
  if (value == null || !value.isFinite) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'MySQL returned a non-finite or invalid number.',
    );
  }
  return SqlValue.real(value);
}

SqlValue _readTimestamp(Object raw, {required bool binary}) {
  if (raw is DateTime) return SqlValue.time(raw);
  if (raw is! String) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'MySQL returned an invalid timestamp.',
    );
  }

  final match = _timestampPattern.firstMatch(raw);
  if (match == null) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'MySQL returned an invalid timestamp.',
    );
  }

  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final hour = int.parse(match[4] ?? '0');
  final minute = int.parse(match[5] ?? '0');
  final second = int.parse(match[6] ?? '0');
  final fraction = match[7];
  final microsecond = fraction == null
      ? 0
      : binary
      ? int.parse(fraction)
      : int.parse(fraction.padRight(6, '0'));

  if (year < 1 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59 ||
      microsecond > 999999) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'MySQL returned an invalid timestamp.',
    );
  }

  final value = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    microsecond ~/ 1000,
    microsecond % 1000,
  );
  if (value.year != year ||
      value.month != month ||
      value.day != day ||
      value.hour != hour ||
      value.minute != minute ||
      value.second != second) {
    throw const SqlException(
      SqlErrorCode.invalidRow,
      'MySQL returned an invalid timestamp.',
    );
  }
  return SqlValue.time(value);
}

SqlValue _readScalar(Object raw) {
  return switch (raw) {
    final String value => SqlValue.text(value),
    final Uint8List value => SqlValue.blob(value),
    final int value => SqlValue.integer(value),
    final double value when value.isFinite => SqlValue.real(value),
    double() => throw const SqlException(
      SqlErrorCode.invalidRow,
      'MySQL returned a non-finite number.',
    ),
    final bool value => SqlValue.boolean(value),
    final DateTime value => SqlValue.time(value),
    final Object value => throw SqlException(
      SqlErrorCode.invalidRow,
      'MySQL returned unsupported ${value.runtimeType} data.',
    ),
  };
}

int _checkedNonNegativeInt(BigInt value, String field) {
  if (value.isNegative || !value.isValidInt) {
    throw SqlException(
      SqlErrorCode.invalidRow,
      'MySQL returned an invalid $field value.',
    );
  }
  return value.toInt();
}

final RegExp _timestampPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})'
  r'(?:[ T](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?)?$',
);
