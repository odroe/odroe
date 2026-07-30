import 'dart:async';
import 'dart:io';

import 'package:mysql_dart/exception.dart' as mysql;

import '../database/error.dart';

/// Runs one driver operation and maps failures without retaining SQL values.
Future<T> runMysql<T>(
  FutureOr<T> Function() action, {
  required String operation,
  bool connected = true,
}) async {
  try {
    return await action();
  } on SqlException {
    rethrow;
  } on mysql.MySQLServerException catch (error) {
    throw mapMysqlServerError(error);
  } on SocketException catch (error) {
    throw _unavailable(error);
  } on TimeoutException catch (error) {
    throw _unavailable(error);
  } on IOException catch (error) {
    throw _unavailable(error);
  } on mysql.MySQLClientException catch (error) {
    final unavailable = operation == 'connect' || !connected;
    throw SqlException(
      unavailable ? SqlErrorCode.unavailable : SqlErrorCode.driver,
      unavailable ? 'MySQL is unavailable.' : 'MySQL $operation failed.',
      cause: MysqlCause(error.runtimeType.toString()),
    );
  } on ArgumentError catch (error) {
    throw SqlException(
      SqlErrorCode.invalidValue,
      'MySQL rejected a bound value.',
      cause: MysqlCause(error.runtimeType.toString()),
    );
  } on Exception catch (error) {
    throw SqlException(
      SqlErrorCode.driver,
      'MySQL $operation failed.',
      cause: MysqlCause(error.runtimeType.toString()),
    );
  }
}

/// Maps a structured MySQL server error number to a portable category.
SqlException mapMysqlServerError(mysql.MySQLServerException error) {
  final number = error.errorCode;
  final code = switch (number) {
    1048 ||
    1062 ||
    1169 ||
    1216 ||
    1217 ||
    1364 ||
    1451 ||
    1452 ||
    1557 ||
    1586 ||
    3819 ||
    4025 => SqlErrorCode.constraint,
    1264 ||
    1265 ||
    1292 ||
    1366 ||
    1406 ||
    1411 ||
    1690 ||
    3140 => SqlErrorCode.invalidValue,
    1040 ||
    1042 ||
    1043 ||
    1045 ||
    1129 ||
    1130 ||
    1152 ||
    1153 ||
    1154 ||
    1155 ||
    1156 ||
    1157 ||
    1158 ||
    1159 ||
    1160 ||
    1161 ||
    1205 ||
    1213 => SqlErrorCode.unavailable,
    _ => SqlErrorCode.driver,
  };
  return SqlException(code, switch (code) {
    SqlErrorCode.constraint => 'A MySQL constraint rejected the operation.',
    SqlErrorCode.invalidValue => 'MySQL rejected a bound value.',
    SqlErrorCode.unavailable => 'MySQL is unavailable.',
    _ => 'MySQL operation failed.',
  }, cause: MysqlCause(error.runtimeType.toString(), errorNumber: number));
}

/// Sanitized MySQL failure metadata.
final class MysqlCause {
  /// Creates sanitized driver metadata.
  const MysqlCause(this.driverType, {this.errorNumber});

  /// Runtime type of the original driver exception.
  final String driverType;

  /// Structured MySQL server error number, when available.
  final int? errorNumber;

  @override
  String toString() {
    final number = errorNumber;
    return number == null ? driverType : '$driverType (error $number)';
  }
}

SqlException _unavailable(Object error) => SqlException(
  SqlErrorCode.unavailable,
  'MySQL is unavailable.',
  cause: MysqlCause(error.runtimeType.toString()),
);
