@JS()
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:odroe/database_d1.dart';
import 'package:odroe/server_fetch.dart';

import 'routes.server.dart' as generated;

FutureOr<Server> createServer() => generated.createServer(
  invocationModules: (invocation) {
    final bindings = invocation.requireBindings<FetchBindings>();
    final environment = _Environment(bindings.raw);
    return <DatabaseModule>[
      DatabaseModule.owned(D1SqlDatabase.fromBinding(environment.database)),
    ];
  },
);

extension type _Environment(JSObject _) implements JSObject {
  @JS('DB')
  external JSObject get database;
}
