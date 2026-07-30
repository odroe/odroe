import 'package:odroe/database.dart';
import 'package:test/test.dart';

void main() {
  test('SqlRow preserves duplicate column names by index', () {
    final row = SqlRow(
      <String>['id', 'id'],
      <SqlValue>[const SqlValue.integer(7), const SqlValue.integer(9)],
    );

    expect(row.length, 2);
    expect(row.nameAt(0), 'id');
    expect(row.nameAt(1), 'id');
    expect(row.read(0, sqlInt), 7);
    expect(row.read(1, sqlInt), 9);
  });

  test('SqlRow defensively copies columns and values', () {
    final columns = <String>['id'];
    final values = <SqlValue>[const SqlValue.integer(7)];
    final row = SqlRow(columns, values);

    columns[0] = 'changed';
    values[0] = const SqlValue.integer(9);

    expect(row.nameAt(0), 'id');
    expect(row.valueAt(0).value, 7);
  });

  test('SqlRow rejects mismatched columns and values', () {
    expect(
      () => SqlRow(
        <String>['id', 'email'],
        <SqlValue>[const SqlValue.integer(7)],
      ),
      throwsArgumentError,
    );
  });

  test('SqlColumn validates the expected result label', () {
    const id = SqlColumn<int>('id', sqlInt);
    final row = SqlRow(
      <String>['user_id'],
      <SqlValue>[const SqlValue.integer(7)],
    );

    expect(() => id.read(row, 0), _throwsSql(SqlErrorCode.invalidRow));
    expect(id.as('user_id').read(row, 0), 7);
    expect(() => id.as(''), throwsArgumentError);
  });

  test('SqlRow reports invalid indices as row errors', () {
    final row = SqlRow(<String>['id'], <SqlValue>[const SqlValue.integer(7)]);

    expect(() => row.nameAt(-1), _throwsSql(SqlErrorCode.invalidRow));
    expect(() => row.valueAt(1), _throwsSql(SqlErrorCode.invalidRow));
  });

  test('SqlRow wraps codec failures with column context', () {
    const email = SqlColumn<String>('email', sqlText);
    final row = SqlRow(
      <String>['email'],
      <SqlValue>[const SqlValue.integer(7)],
    );

    expect(
      () => email.read(row, 0),
      throwsA(
        isA<SqlException>()
            .having((error) => error.code, 'code', SqlErrorCode.invalidRow)
            .having((error) => error.message, 'message', contains('email'))
            .having((error) => error.cause, 'cause', isA<SqlException>()),
      ),
    );
  });

  test('SqlColumn wraps bind failures with column context', () {
    const value = SqlColumn<String>('payload', _FailingCodec());

    expect(
      () => value.bind('secret'),
      throwsA(
        isA<SqlException>()
            .having((error) => error.code, 'code', SqlErrorCode.invalidValue)
            .having((error) => error.message, 'message', contains('payload'))
            .having(
              (error) => error.message,
              'message',
              isNot(contains('secret')),
            ),
      ),
    );
  });

  test('SqlRow and SqlColumn do not disguise programming errors', () {
    const value = SqlColumn<String>('payload', _ProgrammingErrorCodec());
    final row = SqlRow(
      <String>['payload'],
      <SqlValue>[const SqlValue.text('value')],
    );

    expect(() => value.read(row, 0), throwsStateError);
    expect(() => value.bind('value'), throwsStateError);
  });
}

Matcher _throwsSql(SqlErrorCode code) =>
    throwsA(isA<SqlException>().having((error) => error.code, 'code', code));

final class _FailingCodec implements SqlCodec<String> {
  const _FailingCodec();

  @override
  String decode(SqlValue value) => throw const FormatException('invalid');

  @override
  SqlValue encode(String value) => throw const FormatException('invalid');
}

final class _ProgrammingErrorCodec implements SqlCodec<String> {
  const _ProgrammingErrorCodec();

  @override
  String decode(SqlValue value) => throw StateError('codec bug');

  @override
  SqlValue encode(String value) => throw StateError('codec bug');
}
