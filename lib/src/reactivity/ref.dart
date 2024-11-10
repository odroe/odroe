import 'dependency.dart';

abstract interface class Ref<T> {
  T get value;
}

abstract interface class WritableRef<T> extends Ref<T> {
  set value(T _);
}

final class ShallowWritableRef<T> extends WritableRef<T> {
  ShallowWritableRef._(this.raw);

  T raw;
  late final dep = Dependency();

  @override
  T get value {
    dep.track();
    return raw;
  }

  @override
  set value(T value) {
    if (identical(raw, value)) return;
    raw = value;
    dep.trigger();
  }
}
