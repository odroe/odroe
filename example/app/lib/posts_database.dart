import 'package:odroe/database.dart';

import 'posts.dart';

final class Posts extends SqlTable<Post> {
  Posts() : super('posts');

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<String> title = column<String>('title', sqlText);

  @override
  late final SqlProjection<Post> projection = SqlProjection<Post>(
    <SqlSelection<Object?>>[id, title],
    (row) => (id: id.read(row, 0), title: title.read(row, 1)),
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
  await postQueries
      .insertOnConflictDoNothing(
        posts,
        <SqlAssignment>[posts.id.set(42), posts.title.set('SQLite post 42')],
        target: [posts.id],
      )
      .execute(database);
}
