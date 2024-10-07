import 'package:flutter/widgets.dart';

import 'eval_context.dart';
import 'provided.dart';

final _targets = Expando<Map<Object, WeakReference<Element>>>();

/// Injects a value of type [T] provided by an ancestor widget or globally.
///
/// [context] is the current build context.
/// [key] is an optional key to differentiate between multiple instances of the same type.
///
/// Returns the injected value, or null if not found.
T? inject<T>(BuildContext context, [Object? key]) {
  evalContextRef.value = context;

  final element = context as Element;
  final storeKey = key ?? T;

  // Cached target ancestor
  final ancestor = _targets[element]?[storeKey]?.target;
  if (ancestor != null) {
    final values = provides[ancestor];
    if (values != null && values.containsKey(storeKey)) {
      final provided = values[key]!;
      if (provided.value is T) {
        provided.track(element);

        return provided.value;
      }
    }
  }

  // Search ancestors
  T? result;
  element.visitAncestorElements((ancestor) {
    final values = provides[ancestor];
    if (values != null && values.containsKey(storeKey)) {
      final provided = values[storeKey]!;
      if (provided.value is T) {
        provided.track(element);
        result = provided.value;
        return false;
      }
    }

    return true;
  });

  // Find global provides.
  if (result == null) {
    final provided = globalProvides[storeKey];
    if (provided != null && provided.value is T) {
      result = provided.value;
      provided.track(element);
    }
  }

  return result;
}
