import 'corss_link.dart';

Subscriber? _activeSub;
Subscriber? get activeSub => _activeSub;
void Function() setActiveSub(Subscriber sub) {
  final prev = activeSub;
  _activeSub = sub;
  return () => _activeSub = prev;
}

abstract interface class Subscriber {
  abstract int flags;
  Subscriber? next;
  CrossLink? depsHead;
  CrossLink? depsTail;

  void notify();
}
