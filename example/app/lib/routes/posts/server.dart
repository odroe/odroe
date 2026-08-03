import 'package:odroe/database.dart';
import 'package:odroe/server.dart';

import '../../posts.dart' as models;
import '../../posts_database.dart';
import 'route.dart' as definition;

final route = definition.route.server();

final listPosts = ServerFunction<models.ListPostsInput, models.PostPage>(
  id: 'posts.list',
  method: HttpMethod.get,
  handler: (context) async {
    final input = context.data;
    if (input.ids.length > 100) {
      throw const HttpError(
        400,
        'Post ID filter cannot contain more than 100 values.',
      );
    }
    if (input.limit < 1 || input.limit > 50) {
      throw const HttpError(400, 'Post page limit must be between 1 and 50.');
    }
    final order = switch (input.sort) {
      'newest' => posts.id.descending,
      'oldest' => posts.id.ascending,
      _ => throw const HttpError(400, 'Invalid post sort.'),
    };
    final cursor = input.cursor;
    final cursorPredicate = cursor == null
        ? null
        : input.sort == 'newest'
        ? posts.id.lessThan(cursor)
        : posts.id.greaterThan(cursor);
    final idPredicate = input.ids.isEmpty ? null : posts.id.isIn(input.ids);
    final where = switch ((idPredicate, cursorPredicate)) {
      (final ids?, final after?) => ids.and(after),
      (final ids?, null) => ids,
      (null, final after?) => after,
      (null, null) => null,
    };
    final rows = await postQueries
        .selectTable(
          posts,
          where: where,
          orderBy: <SqlOrder>[order],
          limit: input.limit + 1,
        )
        .all(context.request.read(databaseKey));
    final hasNextPage = rows.length > input.limit;
    final items = rows.take(input.limit).toList(growable: false);
    return (items: items, nextCursor: hasNextPage ? items.last.id : null);
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
