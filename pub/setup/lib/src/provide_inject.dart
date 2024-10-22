import 'package:oinject/oinject.dart' as oinject;
// ignore: implementation_imports
import 'package:oinject/src/provided.dart' as oinject;

import 'global.dart';

void provide<T>(T value, {Object? key}) {
  if (currentElement == null) {
    return oinject.provide.global<T>(value, key: key);
  }

  return oinject.provide<T>(currentElement!, value, key: key);
}

T? inject<T>([Object? key]) {
  if (currentElement == null) {
    final provided = oinject.globalProvides[key ?? T];
    if (provided != null && provided.value is T) {
      return provided.value as T;
    }
  }

  return oinject.inject<T>(currentElement!, key);
}
