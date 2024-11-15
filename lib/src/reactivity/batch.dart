import 'computed_ref_impl.dart';
import 'effect_impl.dart';
import 'flags.dart';
import 'subscriber.dart';

int _depth = 0;
Subscriber? _pendingSub;
Subscriber? _pendingComputed;

void startBatch() => _depth++;
void addBatchSub(Subscriber sub) {
  sub.flags |= Flags.notified;
  if (sub is ComputedRefImpl) {
    sub.next = _pendingComputed;
    _pendingComputed = sub;
    return;
  }

  sub.next = _pendingSub;
  _pendingSub = sub;
}

void flushBatch() {
  if (--_depth > 0) return;
  if (_pendingComputed != null) {
    var element = _pendingComputed;
    _pendingComputed = null;
    while (element != null) {
      final next = element.next;
      element.next = null;
      element.flags &= ~Flags.notified;
      element = next;
    }
  }

  Object? err;
  while (_pendingSub != null) {
    var element = _pendingSub;
    _pendingSub = null;

    while (element != null) {
      final next = element.next;
      element.next = null;
      element.flags &= ~Flags.notified;
      if (element.flags & Flags.active != 0) {
        try {
          (element as EffectImpl).trigger();
        } catch (e) {
          err ??= e;
        }
      }

      element = next;
    }
  }

  if (err != null) throw err;
}
