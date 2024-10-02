abstract interface class Ref<T> {
  T get value;
  set value(T _);
}

abstract interface class Derived<T> extends Ref<T> {}
