import '../_internal/custom_ref.dart';
import '../_internal/dependency.dart';
import '../_internal/warn.dart';
import '../_internal/writable_ref_impl.dart';
import '../types.dart';

/// Creates a new ref object from [value].
///
/// A ref is a wrapper around a value that makes it reactive, allowing it to
/// be watched for changes. The wrapped value must be passed as [value].
///
/// Returns a [WritableRef<T>] that can be used to get and set the value.
WritableRef<T> ref<T>(T value) {
  if (value is Ref) {
    warn("Cannot wrap another ref into a ref. Did you accidentally nest them?");
  }

  return WritableRefImpl(value);
}

/// Checks if a value is a Ref type.
///
/// Returns true if [value] is a Ref, false otherwise.
bool isRef(value) => value is Ref;

/// Creates a custom ref with custom getter and setter behavior.
///
/// The [fn] parameter is a function that takes track and trigger callbacks
/// and returns a tuple of getter and setter functions.
///
/// [track] is called to track dependencies when the value is accessed.
/// [trigger] is called to notify dependents when the value changes.
///
/// Returns a [WritableRef<T>] that uses the custom getter and setter.
WritableRef<T> customRef<T>(
  (T Function() getter, void Function(T value)) Function(
    void Function() track,
    void Function() trigger,
  ) fn,
) {
  final dep = Dependency();
  final (getter, setter) = fn(dep.track, dep.trigger);

  return CustomRef(getter, setter);
}
