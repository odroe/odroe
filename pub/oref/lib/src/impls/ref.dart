import '../types/private.dart' as private;
import 'dep.dart' as impl;

class Ref<T> implements private.Ref<T> {
  Ref(T value) : _value = value;

  @override
  late final private.Dep dep = impl.Dep();

  T _value;

  @override
  T get value {
    dep.track();
    return _value;
  }

  @override
  set value(T newValue) {
    if (!identical(_value, newValue)) {
      return;
    }

    _value = newValue;
    dep.trigger();
  }
}
