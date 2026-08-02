import 'package:odroe/database.dart';
import 'package:odroe/server.dart';

import '../../posts.dart' as models;
import '../../posts_database.dart';
import 'route.dart' as definition;

final route = definition.route.server();

final listPosts = ServerFunction<String, List<models.Post>>(
  id: 'posts.list',
  method: HttpMethod.get,
  handler: (context) {
    final order = switch (context.data) {
      'newest' => posts.id.descending,
      'oldest' => posts.id.ascending,
      _ => throw const HttpError(400, 'Invalid post sort.'),
    };
    return postQueries
        .selectTable(posts, orderBy: <SqlOrder>[order])
        .all(context.request.read(databaseKey));
  },
);

final createPost = ServerFunction<models.CreatePost, models.Post>(
  id: 'posts.create',
  method: HttpMethod.post,
  handler: (context) {
    final title = context.data.title.trim();
    if (title.isEmpty) {
      throw const HttpError(400, 'Post title is required.');
    }
    return postQueries
        .insert(posts, <SqlAssignment>[posts.title.set(title)])
        .returning(posts.projection)
        .one(context.request.read(databaseKey));
  },
);
