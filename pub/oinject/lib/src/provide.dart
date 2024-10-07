import 'package:flutter/widgets.dart';

import 'eval_context.dart';
import 'provided.dart';

/// Provides a value of type [T] that can be injected into descendant widgets.
///
/// The [context] is the build context of the widget providing the value.
/// The [value] is the actual value to be provided.
/// An optional [key] can be used to differentiate between multiple providers of the same type.
///
/// This function stores the provided value in the widget tree, making it available
/// for injection in descendant widgets using the [inject] function.
///
/// If a value of the same type (or with the same key) already exists, it will be updated,
/// and any widgets depending on it will be rebuilt.
void provide<T>(BuildContext context, T value, {Object? key}) {
  evalContextRef.value = context;

  final values = provides[context] ??= {};
  final storeKey = key ?? T;
  Provided? provided = values[storeKey];

  if (provided == null || provided.value is! T) {
    provided = values[storeKey] = Provided<T>(value, provided?.deps);
  } else if (!identical(value, provided.value)) {
    provided.value = value;
  }

  provided.trigger();
}
