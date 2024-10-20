import '../types/private.dart' as private;
import 'dep.dart' as impl;

abstract base class BaseRef<T> implements private.Ref<T> {
  BaseRef(this.raw);

  @override
  T raw;

  @override
  late final private.Dep dep = impl.Dep();

  @override
  T get value {
    dep.track();
    return raw;
  }

  @override
  set value(T value) {
    if (identical(raw, value)) {
      return;
    }

    raw = value;
    dep.trigger();
  }
}

base class Ref<T> extends BaseRef<T> {
  Ref(super.raw);
}
