import 'package:odroe/database_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('row counts', () {
    for (final dialect in SqlDialect.values) {
      test('${dialect.name} compiles a bound filtered count', () {
        final users = _Users();
        final quote = dialect == SqlDialect.mysql ? '`' : '"';
        final count = SqlQueries(dialect).countRows(
          users,
          where: users.active.equals(true).and(users.id.greaterThan(7)),
        );

        expect(count, isA<SqlRead<int>>());
        expect(count.statement.fragments, <String>[
          'SELECT COUNT(*) AS ${quote}count$quote '
              'FROM ${quote}users$quote WHERE (${quote}active$quote = ',
          ' AND ${quote}id$quote > ',
          ')',
        ]);
        expect(_values(count.statement), <Object?>[true, 7]);
        expect(count.statement.kind, SqlStatementKind.rowReturning);
        expect(count.statement.dialect, dialect);
      });

      test('${dialect.name} counts qualified join rows', () {
        final users = _Users();
        final posts = _Posts();
        final quote = dialect == SqlDialect.mysql ? '`' : '"';
        final count = SqlQueries(dialect).countRows(
          users,
          joins: <SqlJoin>[
            SqlJoin.left(posts, on: users.id.equalsColumn(posts.authorId)),
          ],
          where: posts.title.isNotNull,
        );

        expect(
          count.statement.fragments.single,
          'SELECT COUNT(*) AS ${quote}count$quote '
          'FROM ${quote}users$quote AS ${quote}t0$quote '
          'LEFT JOIN ${quote}posts$quote AS ${quote}t1$quote '
          'ON ${quote}t0$quote.${quote}id$quote = '
          '${quote}t1$quote.${quote}author_id$quote '
          'WHERE ${quote}t1$quote.${quote}title$quote IS NOT NULL',
        );
      });
    }

    test('keeps predicates inside the counted relation', () {
      final users = _Users();
      final outsider = _Users();

      expect(
        () => const SqlQueries(
          SqlDialect.sqlite,
        ).countRows(users, where: outsider.active.equals(true)),
        throwsArgumentError,
      );
    });

    test('executes total, filtered, empty, and joined SQLite counts', () async {
      final database = SqliteDatabase.openInMemory();
      addTearDown(database.close);
      await database.execute(
        BoundSql.raw('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            active INTEGER NOT NULL
          ) STRICT
        '''),
      );
      await database.execute(
        BoundSql.raw('''
          CREATE TABLE posts (
            id INTEGER PRIMARY KEY,
            author_id INTEGER REFERENCES users (id),
            title TEXT NOT NULL
          ) STRICT
        '''),
      );
      final users = _Users();
      final posts = _Posts();
      const queries = SqlQueries(SqlDialect.sqlite);

      await database.execute(
        BoundSql.raw('INSERT INTO users (id, active) VALUES (1, 1), (2, 0)'),
      );
      await database.execute(
        BoundSql.raw(
          "INSERT INTO posts (id, author_id, title) VALUES "
          "(1, 1, 'First'), (2, 1, 'Second')",
        ),
      );

      expect(await queries.countRows(users).one(database), 2);
      expect(
        await queries
            .countRows(users, where: users.active.equals(true))
            .one(database),
        1,
      );
      expect(
        await queries
            .countRows(users, where: users.id.isIn(const <int>[]))
            .one(database),
        0,
      );
      expect(
        await queries
            .countRows(
              users,
              joins: <SqlJoin>[
                SqlJoin.left(posts, on: users.id.equalsColumn(posts.authorId)),
              ],
            )
            .one(database),
        3,
      );
    });
  });
}

final class _Users extends SqlTable<({int id, bool active})> {
  _Users() : super('users');

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<bool> active = column<bool>('active', sqlBool);

  @override
  late final SqlProjection<({int id, bool active})> projection =
      SqlProjection<({int id, bool active})>(<SqlSelection<Object?>>[
        id,
        active,
      ], (row) => (id: id.read(row, 0), active: active.read(row, 1)));
}

final class _Posts extends SqlTable<({int id, int? authorId, String title})> {
  _Posts() : super('posts');

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<int?> authorId = column<int?>(
    'author_id',
    nullable(sqlInt),
  );
  late final SqlTableColumn<String> title = column<String>('title', sqlText);

  @override
  late final SqlProjection<({int id, int? authorId, String title})> projection =
      SqlProjection<({int id, int? authorId, String title})>(
        <SqlSelection<Object?>>[id, authorId, title],
        (row) => (
          id: id.read(row, 0),
          authorId: authorId.read(row, 1),
          title: title.read(row, 2),
        ),
      );
}

List<Object?> _values(BoundSql statement) => <Object?>[
  for (final value in statement.values) value.value,
];
