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
