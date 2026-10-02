import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/query_flutter.dart';

final _key = QueryKey<int>('provider-value');

void main() {
  testWidgets('default provider creates an isolated client and clears it', (
    tester,
  ) async {
    late QueryClient first;
    await tester.pumpWidget(
      QueryClientProvider(child: _read((client) => first = client)),
    );
    _seed(first, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(first.getQueryData(_key), isNull);

    late QueryClient second;
    await tester.pumpWidget(
      QueryClientProvider(child: _read((client) => second = client)),
    );
    expect(second, isNot(same(first)));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rebuilding and changing create preserve the owned cache', (
    tester,
  ) async {
    var creates = 0;
    late QueryClient first;
    late QueryClient current;
    Widget provider(QueryClient Function() create, String key) =>
        QueryClientProvider(
          key: ValueKey(key),
          create: create,
          child: _read((client) => current = client),
        );
    await tester.pumpWidget(
      provider(() {
        creates++;
        return first = QueryClient();
      }, 'one'),
    );
    _seed(first, 42);
    await tester.pumpWidget(
      provider(
        () => throw StateError('ordinary rebuild recreated the client'),
        'one',
      ),
    );
    expect(current, same(first));
    expect(current.getQueryData(_key), 42);
    expect(creates, 1);

    await tester.pumpWidget(
      provider(() {
        creates++;
        return QueryClient();
      }, 'two'),
    );
    expect(current, isNot(same(first)));
    expect(first.getQueryData(_key), isNull);
    expect(creates, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('owned and borrowed modes release only owned caches', (
    tester,
  ) async {
    final first = QueryClient();
    final external = QueryClient();
    final last = QueryClient();
    addTearDown(external.clear);
    late QueryClient current;
    final child = _read((client) => current = client);
    await tester.pumpWidget(
      QueryClientProvider(create: () => first, child: child),
    );
    _seed(first, 1);
    _seed(external, 2);
    await tester.pumpWidget(
      QueryClientProvider.value(client: external, child: child),
    );
    expect(current, same(external));
    expect(first.getQueryData(_key), isNull);
    expect(external.getQueryData(_key), 2);
    await tester.pumpWidget(
      QueryClientProvider(create: () => last, child: child),
    );
    _seed(last, 3);
    expect(current, same(last));
    expect(external.getQueryData(_key), 2);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(last.getQueryData(_key), isNull);
    expect(external.getQueryData(_key), 2);
    external.clear();
  });

  testWidgets('value can retain an owned instance without clearing it', (
    tester,
  ) async {
    late QueryClient client;
    final child = _read((value) => client = value);
    await tester.pumpWidget(QueryClientProvider(child: child));
    _seed(client, 7);
    await tester.pumpWidget(
      QueryClientProvider.value(client: client, child: child),
    );
    expect(client.getQueryData(_key), 7);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(client.getQueryData(_key), 7);
    client.clear();
  });

  testWidgets('replacing borrowed clients preserves both external caches', (
    tester,
  ) async {
    final first = QueryClient();
    final second = QueryClient();
    addTearDown(first.clear);
    addTearDown(second.clear);
    _seed(first, 1);
    _seed(second, 2);
    late QueryClient current;
    final child = _read((client) => current = client);
    await tester.pumpWidget(
      QueryClientProvider.value(client: first, child: child),
    );
    await tester.pumpWidget(
      QueryClientProvider.value(client: second, child: child),
    );
    expect(current, same(second));
    expect(first.getQueryData(_key), 1);
    expect(second.getQueryData(_key), 2);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(first.getQueryData(_key), 1);
    expect(second.getQueryData(_key), 2);
    first.clear();
    second.clear();
  });

  testWidgets('nested providers isolate caches and keep the outer lifetime', (
    tester,
  ) async {
    late QueryClient outer;
    late QueryClient inner;
    Widget tree(bool includeInner) => QueryClientProvider(
      child: _read(
        (client) => outer = client,
        child: includeInner
            ? QueryClientProvider(child: _read((client) => inner = client))
            : const SizedBox.shrink(),
      ),
    );
    await tester.pumpWidget(tree(true));
    expect(outer, isNot(same(inner)));
    _seed(outer, 1);
    _seed(inner, 2);
    await tester.pumpWidget(tree(false));
    expect(inner.getQueryData(_key), isNull);
    expect(outer.getQueryData(_key), 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(outer.getQueryData(_key), isNull);
  });

  testWidgets('failed creation reports only the original error', (
    tester,
  ) async {
    final error = StateError('client creation failed');
    await tester.pumpWidget(
      QueryClientProvider(
        create: () => throw error,
        child: const SizedBox.shrink(),
      ),
    );
    expect(tester.takeException(), same(error));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed transition to owned never clears the borrowed client', (
    tester,
  ) async {
    final external = QueryClient();
    addTearDown(external.clear);
    _seed(external, 42);
    await tester.pumpWidget(
      QueryClientProvider.value(
        client: external,
        child: const SizedBox.shrink(),
      ),
    );
    final error = StateError('replacement creation failed');
    await tester.pumpWidget(
      QueryClientProvider(
        create: () => throw error,
        child: const SizedBox.shrink(),
      ),
    );
    expect(tester.takeException(), same(error));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(external.getQueryData(_key), 42);
    expect(tester.takeException(), isNull);
    external.clear();
  });

  testWidgets('unmount cancels owned work and ignores a late failure', (
    tester,
  ) async {
    late QueryClient client;
    await tester.pumpWidget(
      QueryClientProvider(child: _read((value) => client = value)),
    );
    final pending = Completer<int>();
    late QueryCancelToken token;
    final future = client.fetchQuery<int>(
      QueryOptions<int>(
        key: _key,
        query: (context) {
          token = context.cancelToken;
          token.markConsumed();
          return pending.future;
        },
      ),
    );
    final cancelled = expectLater(
      future,
      throwsA(isA<QueryCancelledException>()),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await cancelled;
    expect(token.isCancelled, isTrue);
    pending.completeError(StateError('late network failure'));
    await tester.pump();
    expect(client.getQueryData(_key), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('borrowed background work continues after provider unmount', (
    tester,
  ) async {
    final client = QueryClient();
    addTearDown(client.clear);
    final pending = Completer<int>();
    await tester.pumpWidget(
      QueryClientProvider.value(client: client, child: const SizedBox.shrink()),
    );
    final future = client.fetchQuery<int>(
      QueryOptions<int>(key: _key, query: (_) => pending.future),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(42);
    expect(await future, 42);
    expect(client.getQueryData(_key), 42);
    client.clear();
  });

  testWidgets('query errors stay in query state and unmount releases cache', (
    tester,
  ) async {
    late QueryClient client;
    final options = QueryOptions<int>(
      key: _key,
      policy: const QueryPolicy(retry: QueryRetry.never()),
      query: (_) => throw StateError('query failed'),
    );
    await tester.pumpWidget(
      QueryClientProvider(
        child: _read(
          (value) => client = value,
          child: QueryBuilder<int>(
            options: options,
            builder: (_, result) => Text(result.isError ? 'failed' : 'loading'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(client.queryCache.all, isEmpty);
  });

  testWidgets('switching to a borrowed cache ignores the old late result', (
    tester,
  ) async {
    final owned = QueryClient();
    final borrowed = QueryClient();
    addTearDown(borrowed.clear);
    _seed(borrowed, 42);
    final pending = Completer<int>();
    late QueryCancelToken token;
    final options = QueryOptions<int>(
      key: _key,
      policy: const QueryPolicy(freshness: QueryFreshness.never()),
      query: (context) {
        token = context.cancelToken;
        token.markConsumed();
        return pending.future;
      },
    );
    final child = Directionality(
      textDirection: TextDirection.ltr,
      child: QueryBuilder<int>(
        options: options,
        builder: (_, result) =>
            Text(result.hasData ? '${result.requireData}' : 'loading'),
      ),
    );
    await tester.pumpWidget(
      QueryClientProvider(create: () => owned, child: child),
    );
    await tester.pump();
    expect(find.text('loading'), findsOneWidget);
    await tester.pumpWidget(
      QueryClientProvider.value(client: borrowed, child: child),
    );
    await tester.pump();
    expect(find.text('42'), findsOneWidget);
    expect(token.isCancelled, isTrue);
    pending.complete(99);
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
    expect(owned.queryCache.all, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(borrowed.getQueryData(_key), 42);
    borrowed.clear();
  });
}

Widget _read(void Function(QueryClient) record, {Widget? child}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(
        builder: (context) {
          record(QueryClientProvider.of(context));
          return child ?? const SizedBox.shrink();
        },
      ),
    );

void _seed(QueryClient client, int value) {
  client
      .observe(
        QueryOptions<int>(
          key: _key,
          query: (_) => value,
          initialData: QueryInitialData(value),
        ),
      )
      .dispose();
}
