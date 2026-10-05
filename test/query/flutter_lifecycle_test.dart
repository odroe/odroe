import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/odroe_flutter.dart';
import 'package:odroe/query_flutter.dart';

void main() {
  for (final mode in ['default', 'create', 'value', 'module']) {
    for (final state in AppLifecycleState.values) {
      testWidgets('$mode connects with the current $state lifecycle', (
        tester,
      ) async {
        tester.binding.handleAppLifecycleStateChanged(state);
        addTearDown(() {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        });
        final supplied = QueryClient(
          focusManager: QueryFocusManager(
            focused: state != AppLifecycleState.resumed,
          ),
        );
        addTearDown(supplied.clear);
        late QueryClient connected;
        final child = Builder(
          builder: (context) {
            connected = QueryClientProvider.of(context);
            return const SizedBox.shrink();
          },
        );
        await _pumpWidget(tester, switch (mode) {
          'default' => QueryClientProvider(child: child),
          'create' => QueryClientProvider(create: () => supplied, child: child),
          'value' => QueryClientProvider.value(client: supplied, child: child),
          _ => App(
            modules: [QueryModule(client: supplied)],
            builder: (_) => child,
          ),
        });
        expect(
          connected.focusManager.isFocused,
          state == AppLifecycleState.resumed,
        );
        await _pumpWidget(tester, const SizedBox.shrink());
      });
    }
  }

  for (final background in [false, true]) {
    testWidgets('background mount respects refetchInBackground=$background', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      var calls = 0;
      final options = QueryOptions<int>(
        key: QueryKey<int>('poll'),
        policy: QueryPolicy(
          freshness: const QueryFreshness.never(),
          refetchInterval: const Duration(seconds: 1),
          refetchInBackground: background,
        ),
        query: (_) => ++calls,
      );
      await _pumpWidget(tester, QueryClientProvider(child: _query(options)));
      await tester.pumpAndSettle();
      // Initial business reads still run while the application is backgrounded.
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(calls, background ? 2 : 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, background ? 2 : 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(calls, background ? 3 : 2);
      await _pumpWidget(tester, const SizedBox.shrink());
    });
  }

  for (final replacement in [false, true]) {
    testWidgets('retry waits for foreground after '
        '${replacement ? 'client replacement' : 'background mount'}', (
      tester,
    ) async {
      final previous = QueryClient();
      final next = QueryClient();
      addTearDown(previous.clear);
      addTearDown(next.clear);
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      if (replacement) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await _pumpWidget(
          tester,
          QueryClientProvider.value(
            client: previous,
            child: const SizedBox.shrink(),
          ),
        );
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      var calls = 0;
      final options = QueryOptions<int>(
        key: QueryKey<int>('retry'),
        policy: QueryPolicy(
          retry: QueryRetry.times(1),
          retryDelay: (_, _) => const Duration(seconds: 1),
          refetchOnFocus: QueryRefetchPolicy.never,
        ),
        query: (_) {
          if (++calls == 1) throw StateError('temporary failure');
          return 42;
        },
      );
      await _pumpWidget(
        tester,
        QueryClientProvider.value(client: next, child: _query(options)),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        next.getQueryState(options.key)!.fetchStatus,
        QueryFetchStatus.paused,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('42'), findsOneWidget);
      if (replacement) {
        expect(previous.focusManager.isFocused, isFalse);
      }
      await _pumpWidget(tester, const SizedBox.shrink());
      expect(next.getQueryData(options.key), 42);
      previous.clear();
      next.clear();
    });
  }
}

Future<void> _pumpWidget(WidgetTester tester, Widget widget) async {
  // Flutter stops scheduling frames in hidden/paused/detached states. Force
  // mounting here, including App's asynchronous initialization, without sending
  // a new lifecycle event to the provider being tested.
  tester.binding.scheduleForcedFrame();
  await tester.pumpWidget(widget);
  tester.binding.scheduleForcedFrame();
  await tester.pump();
}

Widget _query(QueryOptions<int> options) => Directionality(
  textDirection: TextDirection.ltr,
  child: QueryBuilder<int>(
    options: options,
    builder: (_, result) =>
        Text(result.hasData ? '${result.requireData}' : 'loading'),
  ),
);
