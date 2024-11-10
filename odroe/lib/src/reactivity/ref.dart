abstract interface class Ref<T> {
  T get value;
}

abstract interface class WritableRef<T> extends Ref<T> {
  set value(T _);
}
