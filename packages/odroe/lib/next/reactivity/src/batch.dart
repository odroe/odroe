import '_internal.dart';
import 'effect.dart';

void beginBatch() => batchDepth++;
void endBatch() {
  if (batchDepth > 1) {
    batchDepth--;
    return;
  }

  Object? error;
  bool hasError = false;

  while (batchedEffect != null) {
    Effect? effect = batchedEffect;
    batchedEffect = null;
    batchIteration++;

    while (effect != null) {
      final next = effect.nextBatchedEffect;
      effect.flags &= ~Flag.notified;

      if ((effect.flags & Flag.disposed) == 0 && needsToRecompute(effect)) {
        try {
          effect.callback();
        } catch (err) {
          if (!hasError) {
            error = err;
            hasError = true;
          }
        }
      }
      effect = next;
    }
  }

  batchIteration = 0;
  batchDepth--;

  if (hasError && error != null) {
    throw error;
  }
}

T batch<T>(T Function() fn) {
  if (batchDepth > 0) return fn();

  beginBatch();
  try {
    return fn();
  } finally {
    endBatch();
  }
}
