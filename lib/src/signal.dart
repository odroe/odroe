abstract interface class Signal<T> {
  T get();
}

abstract interface class State<T> implements Signal<T> {
  void set(T value);
}

abstract interface class Computed<T> implements Signal<T> {}
