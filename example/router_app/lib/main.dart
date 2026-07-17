import 'package:flutter/material.dart';
import 'package:odroe/router.dart';

import 'routes.dart';

void main() {
  runApp(const MainApp());
}

final router = OdroeRouter(routes: routeTree);

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(routerConfig: router);
  }
}
