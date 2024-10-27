abstract interface class Ref<T> {
  T get value;
}

abstract interface class WritableRef<T> implements Ref<T> {
  set value(T _);
}

class RefImpl<T> implements WritableRef<T> {
  @override
  T value;
}
