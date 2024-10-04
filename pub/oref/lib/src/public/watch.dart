import '../types/public.dart';
import 'derived.dart' as api;
import 'effect.dart';
import 'scope.dart';

extension type const WatchHandle._(Scope _) {
  void stop() => _.stop();
  void pause() => _.pause();
  void resume() => _.resume();
  void call() => stop();
}

WatchHandle watch<T extends Record>(
  T Function() compute,
  void Function(T value, T? oldValue) runner, {
  bool immediate = false,
  bool once = false,
}) {
  int runCounter = 0;
  final scope = createScope();

  scope.run(() {
    T? oldValue;
    final derived = api.derived<T>(compute);

    effect(() {
      // Track the derived value to trigger the effect.
      final value = derived.value;

      // Skip the first run if immediate is false.
      if (!immediate && runCounter == 0) {
        oldValue = value;
        runCounter++;
        return;
      }

      runner(value, oldValue);

      // If once is true, stop the scope.
      if (once) scope.stop();
      oldValue = value;
      runCounter++;
    });
  });

  return WatchHandle._(scope);
}
