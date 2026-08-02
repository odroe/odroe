import 'package:odroe/database.dart';
import 'package:odroe/server.dart';

import '../../posts.dart' as models;
import '../../posts_database.dart';
import 'route.dart' as definition;

final route = definition.route.server();

final listPosts = ServerFunction<models.ListPostsInput, List<models.Post>>(
  id: 'posts.list',
  method: HttpMethod.get,
  handler: (context) {
    final input = context.data;
    if (input.ids.length > 100) {
      throw const HttpError(
        400,
        'Post ID filter cannot contain more than 100 values.',
      );
    }
    final order = switch (input.sort) {
      'newest' => posts.id.descending,
      'oldest' => posts.id.ascending,
      _ => throw const HttpError(400, 'Invalid post sort.'),
    };
    return postQueries
        .selectTable(
          posts,
          where: input.ids.isEmpty ? null : posts.id.isIn(input.ids),
          orderBy: <SqlOrder>[order],
        )
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
