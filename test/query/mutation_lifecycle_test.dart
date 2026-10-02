import 'dart:async';

import 'package:odroe/query.dart';
import 'package:test/test.dart';

void main() {
  test('clear cancels an offline scoped mutation before it starts', () async {
    final online = QueryOnlineManager(online: false);
    final client = QueryClient(onlineManager: online);
    var calls = 0;
    final future = client.executeMutation<int, int, void>(
      MutationOptions<int, int, void>(
        scope: 'writes',
        mutation: (value, _) {
          calls++;
          return value;
        },
      ),
      1,
    );
    final cancelled = expectLater(
      future,
      throwsA(isA<MutationCancelledException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(client.mutationCache.all.single.state.isPaused, isTrue);
    expect(client.clear, returnsNormally);
    await cancelled;

    online.isOnline = true;
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);
    expect(client.mutationCache.all, isEmpty);
  });

  test('clear cancels serial work waiting behind an active mutation', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final calls = <int>[];
    final client = QueryClient();
    final options = MutationOptions<int, int, void>(
      scope: 'writes',
      mutation: (value, _) async {
        calls.add(value);
        if (value == 1) {
          firstStarted.complete();
          await releaseFirst.future;
        }
        return value;
      },
    );

    final first = client.executeMutation(options, 1);
    await firstStarted.future;
    final second = client.executeMutation(options, 2);
    final secondCancelled = expectLater(
      second,
      throwsA(isA<MutationCancelledException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(client.mutationCache.all.last.state.isPaused, isTrue);
    expect(client.clear, returnsNormally);
    await secondCancelled;

    releaseFirst.complete();
    expect(await first, 1);
    expect(calls, <int>[1]);
    expect(client.mutationCache.all, isEmpty);
  });
}
