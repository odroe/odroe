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

final class ShallowRef<T> extends BaseRef<T> {
  ShallowRef(super.raw);
}

final class CustomRef<T> implements private.Ref<T> {
  const CustomRef(this.dep, this.getter, this.setter);

  final T Function() getter;
  final void Function(T) setter;

  @override
  T get raw => throw UnsupportedError('Custom ref not support read raw value.');

  @override
  set raw(T _) {
    throw UnsupportedError('Custom ref not support set raw value.');
  }

  @override
  T get value => getter();

  @override
  set value(T value) => setter(value);

  @override
  final private.Dep dep;
}
