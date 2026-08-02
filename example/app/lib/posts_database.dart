import 'package:odroe/database.dart';

final class Posts extends SqlTable<String> {
  Posts() : super('posts');

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<String> title = column<String>('title', sqlText);

  @override
  late final SqlProjection<String> projection = SqlProjection<String>.column(
    title,
  );
}

final posts = Posts();
const postQueries = SqlQueries(SqlDialect.sqlite);

Future<void> initializePostsDatabase(SqlDatabase database) async {
  await database.execute(
    BoundSql.raw('''
CREATE TABLE IF NOT EXISTS posts (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL
) STRICT
''', dialect: SqlDialect.sqlite),
  );
  await database.execute(
    BoundSql.raw('''
INSERT INTO posts (id, title) VALUES (42, 'SQLite post 42')
ON CONFLICT(id) DO NOTHING
''', dialect: SqlDialect.sqlite),
  );
}
