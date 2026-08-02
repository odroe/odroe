import 'package:flutter/material.dart';
import 'package:odroe/odroe_flutter.dart';

import 'rpc_origin.dart';
import 'routes.dart';

void main() {
  runApp(
    App(
      webPathUrls: true,
      modules: <Module>[
        QueryModule(),
        RpcModule.http(baseUri: rpcBaseUri()),
        DocumentModule(),
        RouterModule(routes: routeTree),
      ],
      builder: (app) => MaterialApp.router(routerConfig: app.read(routerKey)),
    ),
  );
}
