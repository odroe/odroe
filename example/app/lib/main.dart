import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

import 'routes.dart';

void main() {
  runOdroeApp(
    routes: routeTree,
    builder: (app) => MaterialApp.router(routerConfig: app.router),
  );
}
