import '_depend.dart';
import '_utils.dart';
import 'types.dart';

Ref<T> ref<T>(T value) {
  return _Ref(value);
}

class _Ref<T> implements Ref<T> {
  _Ref(this._value);

  T _value;

  late final Depend dep = Depend();

  @override
  T get value {
    dep.track();
    return _value;
  }

  @override
  set value(T newValue) {
    if (!hasChanged(_value, newValue)) return;
    _value = newValue;
    dep.trigger();
  }
}
