import '../types/public.dart' as public;
import '../impls/derived.dart' as impl;

/// Creates a new [Derived] reference.
///
/// The [getter] function is used to compute the value of the derived reference.
///
/// ```dart
/// final count = ref(0);
/// final doubleCount = derived(() => count.value * 2);
///
/// print(doubleCount.value); // 0
///
/// count.value = 10;
/// print(doubleCount.value); // 20
/// ```
public.Derived<T> derived<T>(T Function() getter) {
  T inner(_) => getter();
  return impl.Derived(inner);
}

/// Utility extension for creating different types of derived references.
extension DerivedUtils on public.Derived<T> Function<T>(T Function() _) {
  /// Creates a writable derived reference.
  ///
  /// The [getter] function computes the value based on the old value.
  /// The [setter] function is used to update the value call.
  ///
  /// ```dart
  /// final count = ref(0);
  /// final doubleCount = derived.writable<int>(
  ///   (_) => count.value * 2, // compute double value
  ///   (value) => count.value = value ~/ 2, // update count value
  /// );
  ///
  /// doubleCount.value = 10; // count.value will be 5
  /// print(count.value); // 5
  ///
  /// count.value = 10; // doubleCount.value will be 20
  /// print(doubleCount.value); // 20
  /// ```
  public.Derived<T> writable<T>(
    T Function(T? oldValue) getter,
    void Function(T newValue) setter,
  ) {
    return impl.Derived(getter, setter);
  }

  /// Creates a derived reference that computes its value based on the previous value.
  ///
  /// The [getter] function computes the value based on the old value.
  ///
  /// **NOTE**: First value is always `null`.
  ///
  /// ```dart
  /// final count = ref(0);
  /// final total = derived.valuable<int>(
  ///   (prev) => count.value + (prev ?? 0)
  /// );
  ///
  /// print(total.value); // 0
  ///
  /// count.value = 10;
  /// print(total.value); // 10
  ///
  /// count.value = 20;
  /// print(total.value); // 30
  /// ```
  public.Derived<T> valuable<T>(T Function(T? oldValue) getter) {
    return impl.Derived(getter);
  }
}
