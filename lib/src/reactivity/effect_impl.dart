import '../warn.dart';
import 'batch.dart';
import 'corss_link.dart';
import 'flags.dart';
import 'subscriber.dart';
import 'tracking.dart';
import 'types.dart';
import 'utils.dart';

final _pausedQueueEffects = Expando<bool>();

final class EffectImpl<T> implements Subscriber, Effect<T> {
  EffectImpl(this.fn, {this.onStop});

  final T Function() fn;
  void Function()? cleanup;
  void Function()? scheduler;

  @override
  CrossLink? depsHead;

  @override
  CrossLink? depsTail;

  @override
  int flags = Flags.active | Flags.tracking;

  @override
  Subscriber? next;

  @override
  void notify() {
    if (flags & Flags.running != 0 && flags & Flags.allowRecurse == 0) {
      return;
    }
    if (flags & Flags.notified == 0) addBatchSub(this);
  }

  @override
  final void Function()? onStop;

  @override
  bool get dirty => isDirty(this);

  @override
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

  @override
  void pause() {
    flags |= Flags.paused;
  }

  @override
  void resume() {
    if (flags & Flags.paused != 0) return;
    flags &= ~Flags.paused;

    if (_pausedQueueEffects[this] == true) {
      _pausedQueueEffects[this] = null;
      trigger();
    }
  }

  @override
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
