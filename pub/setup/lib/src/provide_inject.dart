import 'package:flutter/foundation.dart';

import 'global.dart';

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

T? inject<T>(Object key) {
  return internalInject(key);
}

T injectOr<T>(Object key, T Function() orElse) {
  return internalInject<T>(key, orElse) as T;
}
