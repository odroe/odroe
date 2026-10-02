import 'package:flutter/widgets.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';

import 'counter_page.dart';

class RoutedApp extends StatefulWidget {
  const RoutedApp({required this.greeting, super.key});

  final QueryOptions<String> greeting;

  @override
  State<RoutedApp> createState() => _RoutedAppState();
}

class _RoutedAppState extends State<RoutedApp> {
  late final home = AppRoute<NoParams, NoSearch, NoData>(path: '/').page(
    build: (_) =>
        CounterPage(greeting: widget.greeting, openDetails: openDetails),
  );
  late final details = AppRoute<NoParams, NoSearch, NoData>(path: '/details')
      .page(
        build: (_) => Center(
          child: GestureDetector(onTap: goHome, child: const Text('Back home')),
        ),
      );
  late final AppRouter router = AppRouter(routes: [home, details]);

  void openDetails() => router.go(details.to());

  void goHome() => router.go(home.to());

  @override
  Widget build(BuildContext context) =>
      WidgetsApp.router(color: const Color(0xff222222), routerConfig: router);

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }
}
