import '../types/public.dart' as public;
import '../impls/derived.dart' as impl;

/// Creates a new [public.Derived] instance with the provided getter function.
///
/// The [getter] function is used to compute the value of the derived state.
/// It takes the old value as an optional parameter and returns the new value.
///
/// Returns a [public.Derived<T>] instance.
public.Derived<T> derivedWith<T>(T Function(T? oldValue) getter) {
  return impl.Derived(getter);
}

/// Creates a new [public.Derived] instance with the provided getter function.
///
/// The [getter] function is used to compute the value of the derived state.
/// It takes no parameters and returns the computed value.
///
/// Returns a read-only [public.Derived<T>] instance.
public.Derived<T> derived<T>(T Function() getter) {
  T inner(_) => getter();
  return derivedWith(inner);
}

/// Creates a new writable [public.Derived] instance with the provided getter and setter functions.
///
/// The [getter] function is used to compute the value of the derived state.
/// It takes the old value as an optional parameter and returns the new value.
///
/// The [setter] function is used to update the derived state.
/// It takes the new value as a parameter.
///
/// Returns a writable [public.Derived<T>] instance.
public.Derived<T> writableDerived<T>(
  T Function(T? oldValue) getter,
  void Function(T newValue) setter,
) {
  return impl.Derived(getter, setter);
}
