import '_internal.dart';
import 'batch.dart';

typedef EffectFn = void Function()? Function();

class Effect extends Target {
  EffectFn? fn;
  void Function()? cleanup;

  Effect? nextBatchedEffect;

  Effect([this.fn]) : flags = Flag.tracking;

  void callback() {
    final finish = _start();
    try {
      if ((flags & Flag.disposed) > 0) return;
      if (fn == null) return;

      final cleanup = fn?.call();
      if (cleanup is void Function()) {
        this.cleanup = cleanup;
      }
    } finally {
      finish();
    }
  }

  void Function() _start() {
    if ((flags & Flag.running) > 0) {
      throw Exception('Cycle detected');
    }
    flags |= Flag.running;
    flags &= ~Flag.disposed;

    cleanupEffect(this);
    prepareSources(this);

    beginBatch();
    final prevContext = evalContext;
    evalContext = this;

    return () => endEffect(this, prevContext);
  }

  @override
  void notify() {
    if ((flags & Flag.notified) == 0) {
      flags |= Flag.notified;
      nextBatchedEffect = batchedEffect;
      batchedEffect = this;
    }
  }

  void _dispose() {
    flags |= Flag.disposed;

    if ((flags & Flag.running) == 0) {
      disposeEffect(this);
    }
  }

  @override
  int flags;
}

cleanupEffect(Effect effect) {
  final cleanup = effect.cleanup;
  effect.cleanup = null;

  if (cleanup is Function) {
    beginBatch();

    // Run cleanup functions always outside of any context.
    final prevContext = evalContext;
    evalContext = null;

    try {
      cleanup?.call();
    } catch (err) {
      effect.flags &= ~Flag.running;
      effect.flags |= Flag.disposed;
      disposeEffect(effect);

      rethrow;
    } finally {
      evalContext = prevContext;
      endBatch();
    }
  }
}

disposeEffect(Effect effect) {
  for (Node? node = effect.sources; node != null; node = node.nextSourceNode) {
    node.source.unsubscribe(node);
  }
  effect.fn = null;
  effect.sources = null;

  cleanupEffect(effect);
}

endEffect(Effect effect, dynamic prevContext) {
  if (evalContext != effect) {
    throw Exception('Out-of-order effect');
  }
  cleanupSources(effect);
  evalContext = prevContext;

  effect.flags &= ~Flag.running;
  if ((effect.flags & Flag.disposed) > 0) {
    disposeEffect(effect);
  }
  endBatch();
}

/// Create an effect to run arbitrary code in response to signal changes.
///
/// An effect tracks which signals are accessed within the given callback
/// function `fn`, and re-runs the callback when those signals change.
///
/// The callback may return a cleanup function. The cleanup function gets
/// run once, either when the callback is next called or when the effect
/// gets disposed, whichever happens first.
///
/// @param fn The effect callback.
/// @returns A function for disposing the effect.
void Function() effect(EffectFn fn) {
  final effect = Effect(fn);
  try {
    effect.callback();
  } catch (err) {
    effect._dispose();
    rethrow;
  }
  // Return a bound function instead of a wrapper like `() => effect._dispose()`,
  // because bound functions seem to be just as fast and take up a lot less memory.
  return () => effect._dispose();
}

T untracked<T>(T Function() fn) {
  final prevContext = evalContext;
  evalContext = null;

  try {
    return fn();
  } finally {
    evalContext = prevContext;
  }
}
