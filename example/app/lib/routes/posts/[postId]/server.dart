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
    final title = await postQueries
        .selectTable(posts, where: posts.id.equals(context.data))
        .oneOrNull(context.request.read(databaseKey));
    if (title == null) throw const NotFound('Post not found.');
    return title;
  },
);
