import 'package:flutter/widgets.dart';

import '_provided.dart';

final _targets = Expando<Map<Symbol, WeakReference<Element>>>();

/// Injects a value of type [T] associated with the given [key] from the widget tree.
///
/// This function searches the widget tree upwards from the given [context] to find
/// a provided value matching the specified [key] and type [T]. It first checks a
/// cached ancestor for optimization, then performs a full tree search if necessary.
///
/// Parameters:
/// - [context]: The BuildContext from which to start the search.
/// - [key]: A Symbol used as the identifier for the value to be injected.
///
/// Returns:
/// The injected value of type [T], or null if not found or if the found value
/// doesn't match the expected type.
T? inject<T>(BuildContext context, Symbol key) {
  final element = context as Element;

  // Cached target ancestor
  final ancestor = _targets[element]?[key]?.target;
  if (ancestor != null) {
    final values = provides[ancestor];
    if (values != null && values.containsKey(key)) {
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
    if (values != null && values.containsKey(key)) {
      final provided = values[key]!;
      if (provided.value is T) {
        provided.track(element);
        result = provided.value;
        return false;
      }
    }

    return true;
  });

  return result;
}
