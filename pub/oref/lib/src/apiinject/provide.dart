import 'package:flutter/widgets.dart';

import '../_internal/has_changed.dart';
import '_provided.dart';

/// Provides a value associated with a key in the given BuildContext.
///
/// This function is used to store a value of type [T] associated with a [key]
/// in the context of a specific widget. If the value has changed, it triggers
/// a rebuild of dependent widgets.
///
/// Parameters:
/// - [context]: The BuildContext in which to provide the value.
/// - [key]: A Symbol used as the identifier for the provided value.
/// - [value]: The value to be provided.
void provide<T>(BuildContext context, Symbol key, T value) {
  final values = provides[context] ??= {};
  final provided = values[key];

  if (provided == null || provided is! Provided<T>) {
    values[key] = Provided<T>(value);
    if (provided != null) {
      values[key]!.dependents.addAll(provided.dependents);
    }

    return;
  } else if (hasChanged(provided.value, value)) {
    provided.value = value;
    provided.trigger();
  }
}
