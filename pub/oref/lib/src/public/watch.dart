import '../types/public.dart';
import 'derived.dart';
import 'effect.dart';
import 'scope.dart';

/// A handle for controlling a watch operation.
///
/// Provides methods to stop, pause, and resume the watch.
extension type const WatchHandle._(Scope _) {
  /// Stops the watch operation.
  void stop() => _.stop();

  /// Pauses the watch operation.
  void pause() => _.pause();

  /// Resumes the watch operation.
  void resume() => _.resume();

  /// Stops the watch operation. Alias for [stop].
  void call() => stop();
}

/// Watches a computed value and runs a callback when it changes.
///
/// The [compute] function is used to calculate the value to watch.
/// The [runner] function is called whenever the computed value changes.
///
/// Parameters:
/// - [compute]: A function that returns the value to watch.
/// - [runner]: A callback function that is called with the new and old values.
/// - [immediate]: If true, the [runner] is called immediately on the first run.
/// - [once]: If true, the watch operation stops after the first change.
///
/// Returns a [WatchHandle] that can be used to control the watch operation.
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
    final computed = derived<T>(compute);

    effect(() {
      // Track the derived value to trigger the effect.
      final value = computed.value;

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
