import '../types/private.dart' as private;

/// Checks if a value is reactive object.
///
/// Returns `true` if the value is an instance of `private.Reactive`,
/// otherwise returns `false`.
bool isReactive<T>(T value) => value is private.Reactive;

/// Converts a reactive object to its raw value.
///
/// If the input [value] is a reactive object,
/// this function recursively unwraps it to get the underlying raw value.
/// If the input is not reactive, it is returned as-is.
///
/// ## Example
///
/// ```dart
/// final value = {1, 2}
/// final raw = toRaw(reactiveSet(value));
///
/// print(value == raw); // Prints: true
/// ```
T toRaw<T>(T value) {
  if (value is private.Reactive) {
    return toRaw(value.raw);
  }

  return value;
}
