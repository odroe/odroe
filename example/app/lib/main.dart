import 'package:flutter/material.dart';
import 'package:odroe/document_flutter.dart';
import 'package:odroe/odroe_flutter.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';
import 'package:odroe/rpc.dart';

import 'routes.dart';

void main() {
  runApp(
    App(
      modules: <Module>[
        QueryModule(),
        RpcModule.http(),
        DocumentModule(),
        RouterModule(routes: routeTree),
      ],
      builder: (app) => MaterialApp.router(routerConfig: app.read(routerKey)),
    ),
  );
}
