import '../_internal/computed_ref_impl.dart';
import '../types.dart';
import 'readonly.dart';

/// Returns a readonly computed ref that derives its value from other reactive dependencies.
///
/// The computed ref tracks reactive dependencies and only updates when dependencies change.
///
/// Example:
/// ```dart
/// // Create a source ref
/// final count = ref(0);
///
/// // Create computed ref that doubles the count value
/// final doubled = computed(() => count.value * 2);
///
/// print(doubled.value); // Prints: 0
/// count.value = 2;
/// print(doubled.value); // Prints: 4
/// ```
ReadonlyRef<T, ComputedRef<T>> computed<T>(T Function() fn) {
  return readonly(
    ComputedRefImpl((_) => fn()),
  );
}

/// Provides utility methods for working with computed refs.
///
/// Allows creating writable computed refs with custom getter/setter logic.
extension ComputedUtils on ReadonlyRef<T, ComputedRef<T>> Function<T>(
    T Function()) {
  /// Creates a writable computed ref with a custom getter and optional setter.
  ///
  /// Example:
  /// ```dart
  /// final fullName = computed.writable(
  ///   // Getter combines first and last name
  ///   (oldValue) => '${firstName.value} ${lastName.value}',
  ///   // Setter splits full name into parts
  ///   (value) {
  ///     final parts = value.split(' ');
  ///     firstName.value = parts[0];
  ///     lastName.value = parts[1];
  ///   }
  /// );
  /// ```
  ComputedRef<T> writable<T>(T Function(T? oldValue) getter,
      [void Function(T value)? setter]) {
    return ComputedRefImpl(getter, setter);
  }
}
