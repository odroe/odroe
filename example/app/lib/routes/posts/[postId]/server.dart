import 'package:odroe/database.dart';
import 'package:odroe/router.dart';
import 'package:odroe/server.dart';

import '../../../posts.dart' as models;
import '../../../posts_database.dart';
import 'route.dart' as definition;

final route = definition.route.server(load: (context) => const NoData());

final readPost = ServerFunction<int, models.Post>(
  id: 'posts.read',
  method: HttpMethod.get,
  handler: (context) async {
    final post = await postQueries
        .selectTable(posts, where: posts.id.equals(context.data))
        .oneOrNull(context.request.read(databaseKey));
    if (post == null) throw const NotFound('Post not found.');
    return post;
  },
);
