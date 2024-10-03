import '../types/private.dart' as private;
import 'flags.dart';

int batchDepth = 0;
private.Sub? batchedSub;

void batch(private.Sub sub) {
  sub.flags |= Flags.notified;
  sub.next = batchedSub;
  batchedSub = sub;
}

void startBatch() => batchDepth++;

void endBatch() {
  batchDepth--;
  if (batchDepth > 0) return;

  Object? error;
  while (batchedSub != null) {
    private.Sub? element = batchedSub;

    // 1st pass: clear notified flags
    while (element != null) {
      if ((element.flags & EffectFlags.active) == 0) {
        element.flags &= ~Flags.notified;
      }

      element = element.next;
    }

    element = batchedSub;
    batchedSub = null;

    // 2nd pass: run effects
    while (element != null) {
      final next = element.next;
      element.next = null;
      element.flags &= ~Flags.notified;
      if ((element.flags & EffectFlags.active) != 0) {
        try {
          (element as private.Effect).trigger();
        } catch (e) {
          error ??= e;
        }
      }

      element = next;
    }
  }

  if (error != null) {
    throw error;
  }
}
