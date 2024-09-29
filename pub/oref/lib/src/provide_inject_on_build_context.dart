import 'package:flutter/widgets.dart';

import 'provide_inject.dart' as api;

// Extension on [BuildContext] to add [provide] and [inject] functionality
extension BuildContextProvideInject on BuildContext {
  // Provides a value of type [T] associated with a Symbol key
  // This method delegates to the api.provide function
  // Parameters:
  //   - key: A Symbol that acts as the identifier for the provided value
  //   - value: The value of type [T] to be provided
  void provide<T>(Symbol key, T value) => api.provide(this, key, value);

  // Injects (retrieves) a value of type T associated with a Symbol key
  // This method delegates to the api.inject function
  // Parameters:
  //   - key: A Symbol that acts as the identifier for the value to be retrieved
  // Returns:
  //   - A value of type T if found, or null if not found
  T? inject<T>(Symbol key) => api.inject<T>(this, key);
}
