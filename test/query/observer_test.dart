import 'dart:async';

import 'package:odroe/query.dart';
import 'package:test/test.dart';

void main() {
  test('refetch returns fresh state without a subscription', () async {
    final observer = QueryObserver<int>(
      QueryClient(),
      QueryOptions<int>(key: QueryKey('manual-success'), query: (_) => 42),
    );

    final result = await observer.refetch();

    expect(result.isSuccess, isTrue);
    expect(result.requireData, 42);
    observer.dispose();
  });

  test('refetch returns current error state without a subscription', () async {
    final failure = StateError('failed');
    final observer = QueryObserver<int>(
      QueryClient(),
      QueryOptions<int>(
        key: QueryKey('manual-error'),
        policy: const QueryPolicy(retry: QueryRetry.never()),
        query: (_) => throw failure,
      ),
    );

    final result = await observer.refetch();

    expect(result.isError, isTrue);
    expect(result.error, same(failure));
    observer.dispose();
  });

  test('refetch rebuilds an unobserved query after immediate GC', () async {
    final gate = Completer<int>();
    var calls = 0;
    final client = QueryClient();
    final observer = QueryObserver<int>(
      client,
      QueryOptions<int>(
        key: QueryKey('manual-gc'),
        policy: const QueryPolicy(gcTime: Duration.zero),
        query: (_) {
          calls++;
          return gate.future;
        },
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(client.queryCache.all, isEmpty);

    final refetch = observer.refetch();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(client.queryCache.all, hasLength(1));

    gate.complete(42);
    final result = await refetch;
    expect(result.isSuccess, isTrue);
    expect(result.requireData, 42);
    observer.dispose();
  });

  test('polling reuses a fetch slower than its interval', () async {
    final scheduler = _ManualScheduler();
    final gates = <Completer<int>>[];
    var calls = 0;
    final client = QueryClient(scheduler: scheduler);
    final observer = QueryObserver<int>(
      client,
      QueryOptions<int>(
        key: QueryKey('poll'),
        initialData: QueryInitialData<int>(0, updatedAt: scheduler.now()),
        policy: const QueryPolicy(
          freshness: QueryFreshness.never(),
          refetchInterval: Duration(seconds: 1),
        ),
        query: (_) {
          calls++;
          final gate = Completer<int>();
          gates.add(gate);
          return gate.future;
        },
      ),
    );
    final unsubscribe = observer.subscribe((_) {});

    scheduler.elapse(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    scheduler.elapse(const Duration(seconds: 3));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    gates.single.complete(7);
    await Future<void>.delayed(Duration.zero);
    expect(observer.current.requireData, 7);

    scheduler.elapse(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);

    gates.last.complete(8);
    await Future<void>.delayed(Duration.zero);
    unsubscribe();
    observer.dispose();
  });
}

final class _ManualScheduler implements QueryScheduler {
  DateTime _now = DateTime.utc(2026);
  final List<_ManualTimer> _timers = <_ManualTimer>[];

  @override
  DateTime now() => _now;

  @override
  Timer timer(Duration duration, void Function() callback) {
    final timer = _ManualTimer(_now.add(duration), callback);
    _timers.add(timer);
    return timer;
  }

  void elapse(Duration duration) {
    final target = _now.add(duration);
    while (true) {
      _ManualTimer? next;
      for (final timer in _timers) {
        if (!timer.isActive || timer.due.isAfter(target)) continue;
        if (next == null || timer.due.isBefore(next.due)) next = timer;
      }
      if (next == null) break;
      _now = next.due;
      next.fire();
    }
    _now = target;
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this.due, this._callback);

  final DateTime due;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    _callback();
  }
}
