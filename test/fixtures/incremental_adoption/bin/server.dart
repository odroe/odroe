import 'dart:io';

import 'package:odroe/server_io.dart';

// This fixture is copied into a consumer with a different package name.
// ignore: avoid_relative_lib_imports
import '../lib/greeting.dart';

Future<void> main() async {
  final app = Server(
    routes: const [],
    functions: {
      readGreeting.id: ServerFunctionBinding(
        ServerFunction<NoServerInput, String>(
          handler: (_) => 'Hello from the real server',
        ),
      ),
    },
  );
  final server = await IoServer.bind(app.handle, port: 0);
  stdout.writeln('http://127.0.0.1:${server.port}');
  final stopped = await ProcessSignal.sigterm.watch().first;
  if (stopped == ProcessSignal.sigterm) {
    await server.close();
    await app.close();
  }
}
