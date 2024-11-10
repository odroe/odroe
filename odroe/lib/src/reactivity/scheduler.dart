import 'flags.dart';
import 'subscriber.dart';

int _depth = 0;
Subscriber? _pendingSub;
Subscriber? _pendingComputed;

void addScheduler(Subscriber sub, [bool isComputed = false]) {
  _depth++;
  sub.flags |= Flags.notified;
  if (isComputed) {
    sub.next = _pendingComputed;
    _pendingComputed = sub;
    return;
  }

  sub.next = _pendingSub;
  _pendingSub = sub;
}

void flushScheduler() {
  if (--_depth > 0) return;
  if (_pendingComputed != null) {
    var e = _pendingComputed;
    _pendingComputed = null;

    while (e != null) {
      final next = e.next;
      e.next = null;
      e.flags &= ~Flags.notified;
      e = next;
    }
  }

  Object? err;
  while (_pendingSub != null) {
    var e = _pendingSub;
    _pendingSub = null;

    while (e != null) {
      final next = e.next;

      e.next = null;
      e.flags &= ~Flags.notified;

      if (e.flags & Flags.active != 0) {}
    }
  }
}
