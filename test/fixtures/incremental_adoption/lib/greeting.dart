import 'package:odroe/query.dart';
import 'package:odroe/rpc.dart';

const readGreeting = ServerFunctionRef<NoServerInput, String>(
  id: 'greeting.read',
);

QueryOptions<String> localGreeting() => QueryOptions<String>(
  key: QueryKey<String>('greeting'),
  policy: const QueryPolicy(freshness: QueryFreshness.never()),
  query: (_) async => 'Hello from local data',
);

QueryOptions<String> remoteGreeting(RpcClient rpc) => QueryOptions<String>(
  key: QueryKey<String>('greeting'),
  policy: const QueryPolicy(freshness: QueryFreshness.never()),
  query: (query) => readGreeting(
    rpc,
    const NoServerInput(),
    cancelled: query.cancelToken.whenCancelled.then<void>((_) {}),
  ),
);
