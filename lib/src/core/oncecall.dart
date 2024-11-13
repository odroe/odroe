import 'package:flutter/widgets.dart';

import 'framework.dart';

mixin Oncecall on Element {
  late final _locals = [];
}

int _counter = 0;
final _counterStack = <int>[];

void enableOncecall() {
  _counterStack.add(_counter);
  _counter = 0;
}

void resetOncecall() {
  try {
    _counter = _counterStack.removeLast();
  } catch (_) {
    _counter = 0;
  }
}

T oncecall<T>(T Function() fn) {
  final locals = switch (currentElement) {
    Oncecall(:final _locals) => _locals,
    _ => null,
  };
  if (locals == null) {
    return fn();
  }

  try {
    final exists = locals.elementAtOrNull(_counter);
    if (exists is T) return exists;
    if (locals.isNotEmpty) {
      locals.removeRange(_counter, locals.length);
    }

    final result = fn();
    locals.add(result);

    return result;
  } finally {
    _counter++;
  }
}

Iterable<T> findOncecallResult<T>() {
  return switch (currentElement) {
    Oncecall(:final _locals) => _locals.whereType<T>(),
    _ => const [],
  };
}
