import 'package:odroe/route.dart';
import 'package:odroe/server.dart';

import '../../../models.dart' as models;
import 'route.dart' as definition;

final route = definition.route.server(load: (context) => const NoData());

final readTitle = ServerFunction<int, String>(
  method: HttpMethod.get,
  handler: (context) => 'Post ${context.data}',
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
