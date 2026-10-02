import 'package:odroe/database.dart';

import 'posts.dart';

final class Posts extends SqlTable<Post> {
  Posts() : super('posts');

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<String> title = column<String>('title', sqlText);

  @override
  late final SqlProjection<Post> projection = SqlProjection<Post>(
    columns: [id, title],
    decode: (row) => (id: row.read(id), title: row.read(title)),
  );
}

final posts = Posts();
const postQueries = SqlQueries(SqlDialect.sqlite);
