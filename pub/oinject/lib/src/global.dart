import 'package:flutter/widgets.dart';

import 'provided.dart';

/// Extends the `provide` function with a `global` method for providing global dependencies.
extension GlobalProvider on void Function<T>(BuildContext, T, {Object? key}) {
  /// Provides a global dependency that can be injected anywhere in the application.
  ///
  /// [T] is the type of the value being provided.
  /// [value] is the dependency being provided globally.
  /// [key] is an optional key to differentiate between multiple instances of the same type.
  void global<T>(T value, {Object? key}) {
    final storeKey = key ?? T;
    Provided? provided = globalProvides[storeKey];

    if (provided == null || provided.value is! T) {
      provided = globalProvides[storeKey] = Provided<T>(value, provided?.deps);
    } else if (!identical(provided.value, value)) {
      provided.value = value;
    }

    provided.trigger();
  }
}
