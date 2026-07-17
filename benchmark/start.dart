import 'dart:convert';

import 'package:odroe/start.dart';

Future<void> main() async {
  final app = StartApplication(
    routes: <AnyAppRoute>[AppRoute<NoParams, NoSearch, NoData>(path: '/')],
    functions: <String, AnyServerFunction>{
      'increment': ServerFunction<int, int>(
        handler: (context) => context.data + 1,
      ),
    },
  );
  final client = StartRpcClient(
    baseUri: Uri.parse('http://localhost'),
    transport: InMemoryStartTransport(app.handle),
  );
  const function = ServerFunctionRef<int, int>(id: 'increment');

  for (var index = 0; index < 200; index++) {
    await function.call(client, index);
  }
  final rpc = Stopwatch()..start();
  for (var index = 0; index < 2000; index++) {
    final result = await function.call(client, index);
    if (result != index + 1) throw StateError('Unexpected RPC value.');
  }
  rpc.stop();
  _print('In-memory typed RPC', rpc.elapsed, 2000);

  final route = Stopwatch()..start();
  for (var index = 0; index < 2000; index++) {
    final response = await app.handle(
      StartRequest.bytes(
        method: StartMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: StartHeaders.single(<String, String>{
          'accept': 'application/json',
        }),
      ),
    );
    final payload = jsonDecode(await response.readText()) as Map;
    if (payload['location'] != '/') throw StateError('Unexpected route.');
  }
  route.stop();
  _print('Route + JSON handoff', route.elapsed, 2000);
}

void _print(String name, Duration elapsed, int iterations) {
  final microseconds = elapsed.inMicroseconds / iterations;
  print('$name: ${microseconds.toStringAsFixed(2)} us/op');
}
