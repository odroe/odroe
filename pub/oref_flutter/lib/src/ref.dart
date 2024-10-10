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
