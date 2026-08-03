import 'package:odroe/database.dart';
import 'package:test/test.dart';

void main() {
  group('membership predicates', () {
    for (final dialect in SqlDialect.values) {
      test('${dialect.name} compiles bound membership predicates', () {
        final users = _Users();
        final values = <int>[3, 1, 3];
        final ids = users.id.isIn(values);
        values
          ..clear()
          ..add(99);
        final quote = dialect == SqlDialect.mysql ? '`' : '"';

        final read = SqlQueries(dialect).selectTable(
          users,
          where: ids.and(users.nickname.isNotIn(<String?>['blocked', null])),
        );

        expect(read.statement.fragments, <String>[
          'SELECT ${quote}id$quote, ${quote}nickname$quote '
              'FROM ${quote}users$quote WHERE (${quote}id$quote IN (',
          ', ',
          ', ',
          ') AND (${quote}nickname$quote NOT IN (',
          ') AND ${quote}nickname$quote IS NOT NULL))',
        ]);
        expect(_values(read.statement), <Object?>[3, 1, 3, 'blocked']);
        expect(read.statement.dialect, dialect);
      });
    }

    test('normalizes empty and NULL memberships without invalid SQL', () {
      final users = _Users();
      const queries = SqlQueries(SqlDialect.sqlite);

      expect(
        queries
            .selectTable(users, where: users.id.isIn(const <int>[]))
            .statement
            .fragments
            .single,
        'SELECT "id", "nickname" FROM "users" WHERE 0 = 1',
      );
      expect(() => users.id.isNotIn(const <int>[]), throwsArgumentError);
      expect(
        queries
            .selectTable(users, where: users.nickname.isIn(<String?>[null]))
            .statement
            .fragments
            .single,
        'SELECT "id", "nickname" FROM "users" '
        'WHERE "nickname" IS NULL',
      );
      expect(
        queries
            .selectTable(users, where: users.nickname.isNotIn(<String?>[null]))
            .statement
            .fragments
            .single,
        'SELECT "id", "nickname" FROM "users" '
        'WHERE "nickname" IS NOT NULL',
      );

      final nullable = queries.selectTable(
        users,
        where: users.nickname.isIn(<String?>['Ada', null]),
      );
      expect(nullable.statement.fragments, <String>[
        'SELECT "id", "nickname" FROM "users" '
            'WHERE ("nickname" IN (',
        ') OR "nickname" IS NULL)',
      ]);
      expect(_values(nullable.statement), <Object?>['Ada']);
    });

    test('consumes a lazy candidate iterable exactly once', () {
      final users = _Users();
      var iterations = 0;
      Iterable<int> candidates() sync* {
        iterations++;
        yield 2;
        yield 1;
        yield 2;
      }

      final predicate = users.id.isIn(candidates());
      expect(iterations, 1);
      final first = const SqlQueries(
        SqlDialect.sqlite,
      ).selectTable(users, where: predicate);
      final second = const SqlQueries(
        SqlDialect.postgres,
      ).selectTable(users, where: predicate);

      expect(iterations, 1);
      expect(_values(first.statement), <Object?>[2, 1, 2]);
      expect(_values(second.statement), <Object?>[2, 1, 2]);
    });

    test('normalizes Dart null before invoking a custom codec', () {
      final codec = _NullEncodingCodec();
      final records = _EncodedNulls(codec);
      const queries = SqlQueries(SqlDialect.sqlite);

      final explicitNull = queries.selectTable(
        records,
        where: records.value.isIn(<String?>[null]),
      );
      expect(codec.encodeCalls, 0);
      expect(
        explicitNull.statement.fragments.single,
        'SELECT "value" FROM "encoded_nulls" WHERE "value" IS NULL',
      );

      final encodedNull = queries.selectTable(
        records,
        where: records.value.isIn(<String?>['sentinel']),
      );
      expect(codec.encodeCalls, 1);
      expect(encodedNull.statement.fragments, <String>[
        'SELECT "value" FROM "encoded_nulls" WHERE "value" IN (',
        ')',
      ]);
      expect(_values(encodedNull.statement), <Object?>[null]);
    });

    test('keeps membership columns inside the operation scope', () {
      final users = _Users();
      final other = _Users();
      const queries = SqlQueries(SqlDialect.sqlite);

      expect(
        () => queries.selectTable(users, where: other.id.isIn(<int>[1, 2])),
        throwsArgumentError,
      );
    });
  });
}

final class _EncodedNulls extends SqlTable<String?> {
  _EncodedNulls(SqlCodec<String?> codec) : super('encoded_nulls') {
    value = column<String?>('value', codec);
  }

  late final SqlTableColumn<String?> value;

  @override
  late final SqlProjection<String?> projection = SqlProjection.column(value);
}

final class _NullEncodingCodec implements SqlCodec<String?> {
  var encodeCalls = 0;

  @override
  SqlValue encode(String? value) {
    encodeCalls++;
    return const SqlValue.nullValue();
  }

  @override
  String? decode(SqlValue value) => null;
}

final class _Users extends SqlTable<({int id, String? nickname})> {
  _Users() : super('users');

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<String?> nickname = column<String?>(
    'nickname',
    nullable(sqlText),
  );

  @override
  late final SqlProjection<({int id, String? nickname})> projection =
      SqlProjection<({int id, String? nickname})>(
        columns: [id, nickname],
        decode: (row) => (id: row.read(id), nickname: row.read(nickname)),
      );
}

List<Object?> _values(BoundSql statement) => <Object?>[
  for (final value in statement.values) value.value,
];
