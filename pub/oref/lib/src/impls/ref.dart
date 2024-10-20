import '../types/private.dart' as private;
import 'dep.dart' as impl;

class Ref<T> implements private.Ref<T> {
  Ref(this.raw);

  @override
  late final private.Dep dep = impl.Dep();

  @override
  T raw;

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
