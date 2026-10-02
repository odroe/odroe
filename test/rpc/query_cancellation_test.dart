import 'dart:async';

import 'package:odroe/query.dart';
import 'package:odroe/rpc.dart';
import 'package:test/test.dart';

void main() {
  test('cancelQueries propagates cancellation to RPC', () async {
    final transport = _CancellationTransport();
    final query = QueryClient();
    final options = _rpcQuery(transport);

    final fetch = query.fetchQuery(options);
    await transport.started.future;
    await query.cancelQueries(QueryFilter(key: options.key, exact: true));

    await expectLater(fetch, throwsA(isA<QueryCancelledException>()));
    await expectLater(transport.cancelled.future, completes);
    final state = query.getQueryState<String>(options.key)!;
    expect(state.status, QueryStatus.pending);
    expect(state.fetchStatus, QueryFetchStatus.idle);
    expect(state.error, isNull);
    expect(state.fetchFailureCount, 0);
  });

  test('disposing the last observer cancels an aware RPC query', () async {
    final transport = _CancellationTransport();
    final query = QueryClient();
    final observer = query.observe(_rpcQuery(transport));
    final remove = observer.subscribe((_) {});

    await transport.started.future;
    remove();

    await expectLater(transport.cancelled.future, completes);
    observer.dispose();
  });
}

QueryOptions<String> _rpcQuery(_CancellationTransport transport) {
  final rpc = RpcClient(
    baseUri: Uri.parse('https://api.example.com'),
    transport: transport,
  );
  const function = ServerFunctionRef<NoServerInput, String>(id: 'post.read');
  return QueryOptions<String>(
    key: QueryKey('post', <Object?>[42]),
    query: (context) => function(
      rpc,
      const NoServerInput(),
      cancelled: context.cancelToken.whenCancelled.then<void>((_) {}),
    ),
  );
}

final class _CancellationTransport implements RpcTransport {
  final Completer<void> started = Completer<void>();
  final Completer<void> cancelled = Completer<void>();

  @override
  Future<ServerResponse> send(ServerRequest request) async {
    if (!started.isCompleted) started.complete();
    final signal = request.cancelled;
    if (signal == null) {
      throw StateError('RPC query did not forward cancellation.');
    }
    await signal;
    if (!cancelled.isCompleted) cancelled.complete();
    throw const RpcCancelledException();
  }
}
