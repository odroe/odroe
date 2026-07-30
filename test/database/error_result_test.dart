import 'package:odroe/database.dart';
import 'package:test/test.dart';

void main() {
  test('SqlException retains portable error details', () {
    const cause = FormatException('driver detail');
    const error = SqlException(
      SqlErrorCode.constraint,
      'A unique constraint rejected the write.',
      constraint: 'users_email_key',
      cause: cause,
    );

    expect(error.code, SqlErrorCode.constraint);
    expect(error.constraint, 'users_email_key');
    expect(error.cause, same(cause));
    expect(
      error.toString(),
      'SqlException(constraint): A unique constraint rejected the write.',
    );
  });

  test('SqlWriteResult exposes write metadata from one operation', () {
    final result = SqlWriteResult(affectedRows: 3, lastInsertId: 42);

    expect(result.affectedRows, 3);
    expect(result.lastInsertId, 42);
    expect(() => SqlWriteResult(affectedRows: -1), throwsArgumentError);
    expect(
      () => SqlWriteResult(affectedRows: 1, lastInsertId: -1),
      throwsArgumentError,
    );
  });
}
