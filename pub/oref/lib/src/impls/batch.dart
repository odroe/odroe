import '../types/private.dart' as private;
import 'flags.dart';

int batchDepth = 0;
private.Sub? batchedSub;
private.Sub? batchedDerived;

void batch(private.Sub sub, bool isDerived) {
  sub.flags |= Flags.notified;

  if (isDerived) {
    sub.next = batchedDerived;
    batchedDerived = sub;
    return;
  }

  sub.next = batchedSub;
  batchedSub = sub;
}

void startBatch() => batchDepth++;

void endBatch() {
  batchDepth--;
  if (batchDepth > 0) return;

  if (batchedDerived != null) {
    private.Sub? element = batchedDerived;
    batchedDerived = null;
    while (element != null) {
      final next = element.next;
      element.next = null;
      element.flags &= ~Flags.notified;
      element = next;
    }
  }

  Object? error;
  while (batchedSub != null) {
    private.Sub? element = batchedSub;
    batchedSub = null;

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
