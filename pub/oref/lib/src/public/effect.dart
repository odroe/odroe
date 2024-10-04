import '../impls/utils.dart';
import '../types/public.dart' as public;
import '../types/private.dart' as private;
import '../impls/effect.dart' as impl;
import '../impls/global.dart';

/// Creates and runs an effect.
///
/// - [runner] is the function to run as the effect.
/// - [scheduler] is an optional function to schedule the effect run.
/// - [onStop] is an optional function called when the effect is stopped.
///
/// Returns a [public.Effect<T>] instance.
public.Effect<T> effect<T>(
  T Function() runner, {
  void Function()? scheduler,
  void Function()? onStop,
}) {
  final inner = impl.Effect(
    runner,
    scheduler: scheduler,
    onStop: onStop,
  );

  try {
    inner.run();
  } catch (_) {
    inner.stop();
    rethrow;
  }

  return inner;
}

/// Registers a cleanup function for the current active effect.
///
/// [cleanup] is the function to be called when the effect is cleaned up.
/// [failSilently] determines whether to suppress warnings when called outside an effect.
void onEffectCleanup(void Function() cleanup, [failSilently = false]) {
  if (activeSub is private.Effect) {
    (activeSub as private.Effect).cleanup = cleanup;
  } else if (dev && !failSilently) {
    warn(
      'onEffectCleanup() was called when there was no active effect to associate with.',
    );
  }
}

/// Temporarily pauses tracking.
void pauseTracking() {
  trackStack.add(shouldTrack);
  shouldTrack = false;
}

/// Reenables effect tracking.
void enableTracking() {
  trackStack.add(shouldTrack);
  shouldTrack = true;
}

/// Resets the tracking state to the previous value.
void resetTracking() {
  try {
    shouldTrack = trackStack.removeLast();
  } catch (_) {
    shouldTrack = true;
  }
}
