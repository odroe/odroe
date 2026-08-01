import 'package:odroe/database.dart';
import 'package:odroe/router.dart';
import 'package:odroe/server.dart';

import '../../../posts_database.dart';
import 'route.dart' as definition;

final route = definition.route.server(load: (context) => const NoData());

final readTitle = ServerFunction<int, String>(
  id: 'posts.read-title',
  method: HttpMethod.get,
  handler: (context) async {
    final titles = await postQueries
        .selectTable(posts, where: posts.id.equals(context.data), limit: 1)
        .all(context.request.read(databaseKey));
    if (titles.isEmpty) throw const NotFound('Post not found.');
    return titles.single;
  },
);
