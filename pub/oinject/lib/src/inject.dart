import 'package:flutter/widgets.dart';

import 'eval_context.dart';
import 'provided.dart';

final _targets = Expando<Map<Object, WeakReference<Element>>>();

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

  return result;
}
