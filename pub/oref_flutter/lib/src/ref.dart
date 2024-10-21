import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'internal/widget_effect.dart';

/// Creates a reference to a value of type [T] within the given [BuildContext].
///
/// This function ensures that the widget effect is initialized for the given [context]
/// and returns a reference to the provided [value] using [oref.ref].
///
/// The reference is created only once for each [BuildContext] using [oncecall].
///
/// Example:
/// ```dart
/// final myRef = ref(context, 42);
/// ```
oref.Ref<T> ref<T>(BuildContext context, T value) {
  ensureInitializedWidgetEffect(context);

  return oncecall(context, () => oref.ref(value));
}

/// Creates a custom reference of type [T] within the given [BuildContext].
///
/// This function allows you to create a custom reference with custom getter and setter logic.
/// It takes a [factory] function that receives [track] and [trigger] functions and returns
/// a record containing [get] and [set] functions for the custom reference.
///
/// The [ensureInitializedWidgetEffect] is called to initialize the widget effect for the given [context].
/// The custom reference is created only once for each [BuildContext] using [oncecall].
///
/// Example:
/// ```dart
/// final myCustomRef = customRef<int>(context, (track, trigger) => (
///   get: () {
///     track();
///     return someValue;
///   },
///   set: (newValue) {
///     someValue = newValue;
///     trigger();
///   },
/// ));
/// ```
oref.Ref<T> customRef<T>(
  BuildContext context,
  ({T Function() get, void Function(T) set}) Function(
    void Function() track,
    void Function() trigger,
  ) factory,
) {
  ensureInitializedWidgetEffect(context);

  return oncecall(context, () => oref.customRef(factory));
}
