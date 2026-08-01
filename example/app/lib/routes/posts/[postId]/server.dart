import 'package:odroe/database.dart';
import 'package:odroe/router.dart';
import 'package:odroe/rpc.dart';
import 'package:odroe/server.dart';

import '../../../models.dart' as models;
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

final watchViews = ServerFunction<NoServerInput, Stream<int>>(
  handler: (_) => Stream<int>.fromIterable(const <int>[1, 2, 3]),
);

final doubleValues = ServerFunction<List<int>, List<int>>(
  handler: (context) => context.data.map((value) => value * 2).toList(),
);

final normalizePost = ServerFunction<models.PostId, models.PostId>(
  handler: (context) => models.PostId(context.data.value.abs()),
);
