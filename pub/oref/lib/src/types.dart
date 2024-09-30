abstract interface class Ref<T> {
  T get value;
  set value(T value);
}

abstract interface class ComputedRef<T> implements Ref<T> {
  set valye(T _) => throw StateError('ComputedRef is readonly');
}

typedef RefGetter<T> = T Function();
