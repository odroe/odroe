import 'package:flutter/widgets.dart';
import 'package:odroe/odroe_flutter.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';

final greeting = QueryOptions<String>(
  key: QueryKey<String>('welcome'),
  policy: const QueryPolicy(
    freshness: QueryFreshness.staleAfter(Duration(minutes: 5)),
  ),
  query: (_) async => 'Hello from Odroe',
);

final home = AppRoute<NoParams, NoSearch, NoData>(path: '/').page(
  build: (_) => Center(
    child: QueryBuilder<String>(
      options: greeting,
      builder: (_, result) =>
          Text(result.hasData ? result.requireData : 'Loading'),
    ),
  ),
);

final about = AppRoute<NoParams, NoSearch, NoData>(
  path: '/about',
).page(build: (_) => const Center(child: Text('About this app')));

Widget createApp() => App(
  modules: [
    QueryModule(),
    RouterModule(routes: [home, about]),
  ],
  builder: (app) => WidgetsApp.router(
    color: const Color(0xff222222),
    routerConfig: app.read(routerKey),
  ),
);

void main() => runApp(createApp());
