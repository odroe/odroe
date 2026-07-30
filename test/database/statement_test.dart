import 'package:odroe/database.dart';
import 'package:test/test.dart';

void main() {
  test('BoundSql preserves fragment and value order', () {
    final statement = BoundSql.parts(
      <String>['SELECT * FROM users WHERE email = ', ' AND active = ', ''],
      <SqlValue>[
        const SqlValue.text('ada@example.com'),
        const SqlValue.boolean(true),
      ],
    );

    expect(statement.fragments, <String>[
      'SELECT * FROM users WHERE email = ',
      ' AND active = ',
      '',
    ]);
    expect(statement.values.map((value) => value.value), <Object?>[
      'ada@example.com',
      true,
    ]);
    expect(statement.kind, SqlStatementKind.unknown);
  });

  test('BoundSql defensively copies its inputs', () {
    final fragments = <String>['SELECT ', ''];
    final values = <SqlValue>[const SqlValue.integer(1)];
    final statement = BoundSql.parts(fragments, values);

    fragments[0] = 'DELETE ';
    values[0] = const SqlValue.integer(2);

    expect(statement.fragments, <String>['SELECT ', '']);
    expect(statement.values.single.value, 1);
    expect(() => statement.fragments.add('unexpected'), throwsUnsupportedError);
    expect(
      () => statement.values.add(const SqlValue.integer(3)),
      throwsUnsupportedError,
    );
  });

  test('BoundSql leaves placeholder-like source text untouched', () {
    final statement = BoundSql.parts(
      <String>[
        "SELECT '?' AS question, '\$1' AS postgres_value WHERE id = ",
        ' -- ? and \$2 stay source text',
      ],
      <SqlValue>[const SqlValue.integer(7)],
    );

    expect(
      statement.fragments.first,
      "SELECT '?' AS question, '\$1' AS postgres_value WHERE id = ",
    );
    expect(statement.fragments.last, ' -- ? and \$2 stay source text');
  });

  test('BoundSql.raw contains no bound values', () {
    final statement = BoundSql.raw('SELECT 1');

    expect(statement.fragments, <String>['SELECT 1']);
    expect(statement.values, isEmpty);
    expect(statement.kind, SqlStatementKind.unknown);
  });

  test('BoundSql preserves explicit statement kinds', () {
    final query = BoundSql.raw('SELECT 1', kind: SqlStatementKind.rowReturning);
    final write = BoundSql.parts(
      <String>['INSERT INTO values_table VALUES (', ')'],
      <SqlValue>[const SqlValue.integer(1)],
      kind: SqlStatementKind.write,
    );

    expect(query.kind, SqlStatementKind.rowReturning);
    expect(write.kind, SqlStatementKind.write);
  });

  test('BoundSql rejects invalid fragment arity', () {
    expect(() => BoundSql.parts(<String>[], <SqlValue>[]), throwsArgumentError);
    expect(
      () => BoundSql.parts(
        <String>['SELECT ', ' AND ', ''],
        <SqlValue>[const SqlValue.integer(1)],
      ),
      throwsArgumentError,
    );
  });
}
