import 'package:flutter/foundation.dart';

/// A reactive and mutable reference object.
///
/// [Ref] represents a reactive reference that can be observed and modified.
/// It provides a way to create and manage reactive state in applications.
abstract interface class Ref<T> {
  /// Gets the current value of the reference.
  ///
  /// Returns the current value stored in the reference.
  T get value;

  /// Sets a new value for the reference.
  ///
  /// Updates the value of the reference with the provided value.
  /// This may trigger reactivity and notify observers of the change.
  set value(T _);
}

/// A reactive and readonly reference object.
///
/// [ComputedRef] represents a reactive reference that is computed based on other
/// reactive values. It is readonly and cannot be directly modified.
abstract class ComputedRef<T> implements Ref<T> {
  const ComputedRef();

  /// Throws an error when attempting to set the value of a computed reference.
  ///
  /// [ComputedRef] values are derived and cannot be directly set.
  /// Attempting to set the value will result in a [StateError].
  @override
  @nonVirtual
  set value(_) => throw StateError('ComputedRef is readonly');
}
