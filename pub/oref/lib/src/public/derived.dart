import '../types/public.dart' as public;
import '../impls/derived.dart' as impl;

/// Creates a new [Derived] instance with the provided getter and optional setter.
///
/// The [getter] function is used to compute the value of the derived state.
/// It takes the old value as an optional parameter and returns the new value.
///
/// The optional [setter] function can be provided to allow updating the derived state.
/// It takes the new value as a parameter.
///
/// Returns a [public.Derived<T>] instance.
public.Derived<T> derived<T>(
  T Function(T? oldValue) getter, [
  void Function(T)? setter,
]) {
  return impl.Derived<T>(getter, setter);
}

/// Extension on the [derived] function to provide additional utility methods.
extension DerivedHelper on public.Derived<T> Function<T>(
  T Function(T?), [
  void Function(T)?,
]) {
  /// Creates a readonly [public.Derived] instance with the provided getter function.
  ///
  /// The [getter] function is used to compute the value of the derived state.
  /// It takes no parameters and returns the computed value.
  ///
  /// Returns a [public.Derived<T>] instance.
  public.Derived<T> readonly<T>(T Function() getter) {
    return derived<T>((_) => getter());
  }
}
