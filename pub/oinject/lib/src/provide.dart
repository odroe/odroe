import 'package:flutter/widgets.dart';

import 'eval_context.dart';
import 'provided.dart';

void provide<T>(BuildContext context, T value, {Object? key}) {
  evalContextRef.value = context;

  final values = provides[context] ??= {};
  final storeKey = key ?? T;
  final provided = values[storeKey];

  if (provided == null || provided.value is! T) {
    values[storeKey] = Provided<T>(value);
    if (provided != null) {
      values[storeKey]!.deps.addAll(provided.deps);
    }

    return;
  } else if (!identical(value, provided.value)) {
    provided.value = value;
    provided.trigger();
  }
}
