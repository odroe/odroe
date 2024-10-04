import '../types/private.dart' as private;
import 'batch.dart' as impl;
import 'sub.dart' as impl;
import 'link.dart' as impl;
import 'global.dart';
import 'flags.dart';
import 'scope.dart';
import 'utils.dart';
import 'weak.dart';

final pausedQueueEffects = WeakSet<Effect>();

class Effect<T> implements private.Effect<T> {
  Effect(
    this.runner, {
    this.scheduler,
    this.onStop,
  }) : flags = EffectFlags.active | Flags.tracking {
    if (evalScope != null && evalScope!.active) {
      evalScope!.effects.add(this);
    }
  }

  @override
  void Function()? cleanup;

  @override
  private.Link? deps;

  @override
  private.Link? depsTail;

  @override
  int flags;

  @override
  private.Sub? next;

  @override
  final T Function() runner;

  @override
  final void Function()? scheduler;

  @override
  final void Function()? onStop;

  @override
  bool get dirty => impl.isDirty(this);

  @override
  private.Derived? notify() {
    if ((flags & Flags.running) != 0 && (flags & Flags.allowRecurse) == 0) {
      return null;
    }

    if ((flags & Flags.notified) == 0) {
      impl.batch(this, false);
    }

    return null;
  }

  @override
  void pause() {
    flags |= Flags.paused;
  }

  @override
  void resume() {
    if ((flags & Flags.paused) != 0) {
      flags &= ~Flags.paused;
      if (pausedQueueEffects.contains(this)) {
        pausedQueueEffects.remove(this);
        trigger();
      }
    }
  }

  @override
  T run() {
    if ((flags & EffectFlags.active) == 0) {
      return runner();
    }

    flags |= Flags.running;

    cleanupEffect(this);
    impl.prepareDeps(this);

    final prevSub = activeSub;
    final prevShouldTrack = shouldTrack;

    activeSub = this;
    shouldTrack = true;

    try {
      return runner();
    } finally {
      if (dev && activeSub != this) {
        warn('Active effect was not restored correctly');
      }

      impl.cleanupDeps(this);
      activeSub = prevSub;
      shouldTrack = prevShouldTrack;
      flags &= ~Flags.running;
    }
  }

  @override
  void runIfDirty() {
    if (impl.isDirty(this)) {
      run();
    }
  }

  @override
  void stop() {
    if ((flags & EffectFlags.active) == 0) {
      return;
    }

    for (var link = deps; link != null; link = link.nextDep) {
      impl.removeSub(link);
    }

    deps = depsTail = null;
    impl.cleanupDeps(this);
    onStop?.call();
    flags &= ~EffectFlags.active;
  }

  @override
  void trigger() {
    if ((flags & Flags.paused) != 0) {
      pausedQueueEffects.add(this);
    } else if (scheduler != null) {
      scheduler!();
    } else {
      runIfDirty();
    }
  }
}

void cleanupEffect(Effect effect) {
  final cleanup = effect.cleanup;
  effect.cleanup = null;
  if (cleanup != null) {
    final prevSub = activeSub;
    activeSub = null;

    try {
      cleanup();
    } finally {
      activeSub = prevSub;
    }
  }
}
