import '../types/public.dart' as public;
import '../types/private.dart' as private;
import '../impls/dep.dart' as impl;
import '../impls/ref.dart' as impl;
import '../impls/utils.dart';

/// Creates a value reference.
///
/// **NOTE**: Don't pass in a reference to another value, since it will never be changed.
///
/// ```dart
/// final count = ref(0);
///
/// print(count.value); // 0
///
/// count.value = 10;
/// print(count.value); // 10
/// ```
public.Ref<T> ref<T>(T value) {
  if (value is public.Ref) {
    warn('ref() was called with a Ref instance.');
  }

  return impl.ShallowRef<T>(value);
}

/// Triggers the update of a [Ref] instance.
///
/// If [ref] is an external implementation, a warning is logged in development mode.
///
/// [T] is the type of the value held by the [Ref].
void triggerRef<T>(public.Ref<T> ref) {
  if (ref is private.Ref) {
    (ref as private.Ref).dep.trigger();
  } else if (dev) {
    warn('The ref is an external impl ref, please use your impl trigger.');
  }
}

/// Creates a custom [Ref] with user-defined getter and setter behavior.
///
/// The [factory] function receives [track] and [trigger] functions to manage
/// dependencies and updates, and should return a record with [get] and [set] functions.
///
/// [T] is the type of the value held by the custom [Ref].
///
/// Returns a new [Ref] instance with the custom behavior.
public.Ref<T> customRef<T>(
  ({T Function() get, void Function(T) set}) Function(
    void Function() track,
    void Function() trigger,
  ) factory,
) {
  final dep = impl.Dep();
  final (:get, :set) = factory(dep.track, dep.trigger);

  return impl.CustomRef(dep, get, set);
}

/// Checks if a value is a [Ref] instance.
///
/// Returns `true` if [value] is a [Ref], `false` otherwise.
bool isRef(value) => value is public.Ref;

/// Unwraps a [Ref] instance if the given value is a [Ref], otherwise returns the value as-is.
///
/// If [ref] is a [Ref], returns its value.
/// If [ref] is not a [Ref], returns [ref] unchanged.
///
/// [R] is the type of the unwrapped value.
R unref<R>(ref) {
  if (ref is public.Ref) {
    return ref.value;
  }

  return ref;
}
