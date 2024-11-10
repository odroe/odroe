import 'batch.dart';
import 'corss_link.dart';
import 'dependency.dart';
import 'flags.dart';
import 'subscriber.dart';
import 'warn.dart';

bool shouldTrack = true;
final _trackStack = <bool>[];

/// Temporarily pauses tracking.
void pauseTracking() {
  _trackStack.add(shouldTrack);
  shouldTrack = false;
}

/// Re-enables tracking.
void enableTracking() {
  _trackStack.add(shouldTrack);
  shouldTrack = true;
}

/// Resets the previous global tracking state.
void resetTracking() {
  try {
    shouldTrack = _trackStack.removeLast();
  } catch (_) {
    shouldTrack = true;
  }
}

abstract interface class EffectOptions {
  void Function()? scheduler;
  void Function()? onStop;
}

final class EffectRunner<T> {
  const EffectRunner._(this._innerEffect);
  final Effect<T> _innerEffect;

  Effect<T> get effect => _innerEffect;

  // T call() => effect.run();
}

final _pausedQueueEffects = Expando<bool>();

final class Effect<T> implements Subscriber, EffectOptions {
  Effect._(this.fn);
  final T Function() fn;

  @override
  CrossLink? depsHead;

  @override
  CrossLink? depsTail;

  @override
  int flags = Flags.active | Flags.tracking;

  @override
  Subscriber? next;

  @override
  void Function()? onStop;

  @override
  void Function()? scheduler;

  void Function()? cleanup;

  void pause() {
    flags |= Flags.paused;
  }

  void resume() {
    if (flags & Flags.paused != 0) return;
    flags &= ~Flags.paused;

    if (_pausedQueueEffects[this] == true) {
      _pausedQueueEffects[this] = null;
      trigger();
    }
  }

  @override
  void notify() {
    if ((flags & Flags.running != 0 && flags & Flags.allowRecurse == 0) ||
        flags & Flags.notified == 0) {
      return;
    }

    addBatchSub(this);
  }

  T run() {
    if (flags & Flags.active == 0) {
      return fn();
    }

    flags |= Flags.running;
    cleanupEffect(this);
    prepareDeps(this);
    enableTracking();

    final resetActiveSub = setActiveSub(this);
    try {
      return fn();
    } finally {
      if (activeSub != this) {
        warn(
          'Active effect was not restored correctly -'
          ' this is likely a Vue internal bug.',
        );
      }

      cleanupDeps(this);
      resetActiveSub();
      resetTracking();

      flags &= ~Flags.running;
    }
  }

  void stop() {
    if (flags & Flags.active == 0) return;
    for (var link = depsHead; link != null; link = link.nextDep) {
      removeSub(link);
    }

    depsHead = depsTail = null;
    cleanupEffect(this);
    onStop?.call();
    flags &= ~Flags.active;
  }

  bool get dirty => isDirty(this);

  void trigger() {
    if (flags & Flags.paused != 0) {
      _pausedQueueEffects[this] = true;
    } else if (scheduler != null) {
      scheduler!();
    } else if (dirty) {
      run();
    }
  }
}

void cleanupEffect<T>(Effect<T> effect) {
  final cleanup = effect.cleanup;
  effect.cleanup = null;
  if (cleanup != null) {
    final reset = setActiveSub(null);
    try {
      cleanup();
    } finally {
      reset();
    }
  }
}
