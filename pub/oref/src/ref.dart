abstract interface class ReadonlyRef<T> {
  T get value;
}

abstract interface class WritebleRef<T> implements ReadonlyRef<T> {
  set value(T _);
}

final class ShallowRef<T> implements WritebleRef<T>, ReadonlyRef<T> {
  ShallowRef(this.raw);

  T raw;

  @override
  T get value => throw UnimplementedError();

  @override
  set value(T _) => throw UnimplementedError();
}

bool isRef(Object? value) => value is ShallowRef;
