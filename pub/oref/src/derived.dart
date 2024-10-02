import '_depend.dart';
import '_flags.dart';
import '_subscriber.dart';
import '_warning.dart';
import 'types.dart';

Derived<T> derived<T>(
  T Function() get, {
  void Function(T _)? set,
}) {
  return _Derived(get, set);
}

class _Derived<T> implements Derived<T>, Subscriber {
  _Derived(this.get, [this.set]);

  final T Function() get;
  final void Function(T)? set;

  @override
  late Flags flags = Flags.dirty;

  @override
  Depend? head;

  @override
  Subscriber? next;

  @override
  Depend? tail;

  late T _value;
  late final Depend dep = Depend();

  @override
  T get value {
    dep.track();

    return _value;
  }

  @override
  set value(T newValue) {
    if (set == null) {
      warn('Write failed: Derived value is readonly.');
      return;
    }

    set!(newValue);
  }

  @override
  void notify() {
    flags |= Flags.dirty;

    // TODO: implement notify
  }
}
