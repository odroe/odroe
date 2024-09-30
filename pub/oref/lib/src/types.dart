import 'package:flutter/foundation.dart';

abstract interface class Ref<T> {
  T get value;
  set value(T _);
}

abstract interface class ComputedRef<T> implements Ref<T> {
  @override
  @mustCallSuper
  set value(_) => throw StateError('ComputedRef is readonly');
}
