import 'package:flutter/widgets.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/rpc.dart';

import 'greeting.dart';
import 'routed_app.dart';

class RemoteApp extends StatefulWidget {
  const RemoteApp({required this.origin, super.key});

  final Uri origin;

  @override
  State<RemoteApp> createState() => _RemoteAppState();
}

class _RemoteAppState extends State<RemoteApp> {
  final transport = HttpTransport();
  late final rpc = RpcClient(baseUri: widget.origin, transport: transport);
  late final QueryOptions<String> greeting = remoteGreeting(rpc);

  @override
  Widget build(BuildContext context) =>
      QueryClientProvider(child: RoutedApp(greeting: greeting));

  @override
  void dispose() {
    transport.close();
    super.dispose();
  }
}

void main() {
  const origin = String.fromEnvironment('ODROE_RPC_ORIGIN');
  if (origin.isEmpty) {
    throw ArgumentError('Pass the actual server origin with ODROE_RPC_ORIGIN.');
  }
  runApp(RemoteApp(origin: Uri.parse(origin)));
}
