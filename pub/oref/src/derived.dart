import '_depend.dart';
import '_utils.dart';
import '_warning.dart';
import 'types.dart';

Derived<T> derived<T>(
  T Function() get, {
  void Function(T _)? set,
}) {
  return _Derived(get, set);
}

class _Derived<T> implements Derived<T> {
  _Derived(this.get, [this.set]);

  final T Function() get;
  final void Function(T)? set;

  late T _value;
  late final Depend dep = Depend();

  @override
  T get value {
    dep.track();
    return _value = get();
  }

  @override
  set value(T newValue) {
    if (set == null) {
      warn('Derived value is readonly');
      return;
    } else if (!hasChanged(_value, newValue)) {
      return;
    }

    set!(newValue);
  }
}
