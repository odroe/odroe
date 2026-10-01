import 'package:flutter/material.dart';
import 'package:odroe/document_flutter.dart';
import 'package:odroe/odroe_flutter.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';
import 'package:odroe/rpc.dart';

import 'routes.dart';

void main() {
  const rpcOrigin = String.fromEnvironment('ODROE_RPC_ORIGIN');
  runApp(
    App(
      modules: <Module>[
        QueryModule(),
        RpcModule.http(
          baseUri: rpcOrigin.isEmpty ? null : Uri.parse(rpcOrigin),
        ),
        DocumentModule(),
        RouterModule(routes: routeTree),
      ],
      builder: (app) => MaterialApp.router(routerConfig: app.read(routerKey)),
    ),
  );
}
