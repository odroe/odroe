import 'dart:typed_data';

import '../database/codec.dart';
import '../database/error.dart';
import '../database/statement.dart';

/// A MySQL statement with positional binary-protocol parameters.
final class MysqlBinding {
  /// Creates a positional MySQL binding.
  const MysqlBinding(this.sql, this.parameters);

  /// SQL containing one `?` for every parameter.
  final String sql;

  /// Parameters in placeholder order.
  final List<Object?> parameters;
}

/// Interleaves [BoundSql] fragments with native MySQL `?` placeholders.
///
/// Fragments are never scanned or rewritten.
MysqlBinding bindMysql(BoundSql statement) {
  final sql = StringBuffer(statement.fragments.first);
  final parameters = <Object?>[];
  for (var index = 0; index < statement.values.length; index++) {
    sql
      ..write('?')
      ..write(statement.fragments[index + 1]);
    parameters.add(writeMysqlValue(statement.values[index]));
  }
  return MysqlBinding(sql.toString(), parameters);
}

/// Converts one portable SQL value to a `mysql_dart` parameter.
Object? writeMysqlValue(SqlValue value) {
  return switch (value.value) {
    null => null,
    final int value => value,
    final double value when value.isFinite => value,
    double() => throw const SqlException(
      SqlErrorCode.invalidValue,
      'MySQL cannot bind a non-finite number.',
    ),
    final String value => value,
    final bool value => value,
    final DateTime value => value.toUtc(),
    final Uint8List value => value,
    final Object value => throw SqlException(
      SqlErrorCode.invalidValue,
      'MySQL cannot bind ${value.runtimeType}.',
    ),
  };
}
