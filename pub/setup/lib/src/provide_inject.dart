import 'package:flutter/foundation.dart';

import 'global.dart';

/// Provides a value of type T associated with a key in the current element's scope.
///
/// Must be called within a setup() function. The value will be available for injection
/// in the current element and its children.
///
/// [key] The key to associate the value with
/// [value] The value to provide
void provide<T>(Object key, T value) {
  if (currentElement == null) {
    if (kDebugMode) {
      debugPrint('odroe/setup: provide() can only be used inside setup().');
    }

    return;
  }

  var provides = currentElement!.provides;
  final parentProvides = currentElement!.parent?.provides;

  if (provides == parentProvides) {
    provides = currentElement!.provides = {...?parentProvides};
  }

  provides![key] = value;
}

/// Internal helper function for dependency injection.
///
/// Attempts to retrieve a value of type T associated with the given key from the current
/// element's parent scope. If not found, calls the optional orElse function if provided.
///
/// [key] The key to look up
/// [orElse] Optional function to call if key is not found
/// Returns the injected value or null if not found
T? internalInject<T>(Object key, [T Function()? orElse]) {
  if (currentElement == null) {
    if (kDebugMode) {
      debugPrint('odroe/setup: inject() can only be used inside setup().');
    }
    return null;
  }

  final provides = currentElement!.parent?.provides;
  if (provides != null && provides.containsKey(key)) {
    return provides[key] as T;
  } else if (orElse != null) {
    return orElse();
  } else if (kDebugMode) {
    debugPrint('odroe/setup: inject($key) not fount.');
  }

  return null;
}

/// Injects a value of type T associated with the given key.
///
/// Returns null if the key is not found.
/// Must be called within a setup() function.
T? inject<T>(Object key) {
  return internalInject(key);
}

/// Injects a value of type T associated with the given key, with a fallback.
///
/// Returns the injected value if found, otherwise calls and returns the orElse function.
/// Must be called within a setup() function.
T injectOr<T>(Object key, T Function() orElse) {
  return internalInject<T>(key, orElse) as T;
}
