import 'package:flutter/widgets.dart';

import '_internal/has_changed.dart';

class _Store {
  _Store(this.widget);
  final Widget widget;
  late final Map<Symbol, Object?> values = {};
  late final Map<Symbol, List<WeakReference<Element>>> elements = {};
}

final _refs = Expando<_Store>();
final _targets = Expando<Map<Symbol, WeakReference<Element>>>();

void provide<T>(BuildContext context, Symbol key, T value) {
  var store = _refs[context];
  if (store == null || !Widget.canUpdate(store.widget, context.widget)) {
    store = _refs[context] = _Store(context.widget);
  }

  final hasUpdated = hasChanged(store.values[key], value);
  store.values[key] = value;

  if (hasUpdated) {
    final elements = store.elements[key] ?? [];
    for (final element in elements) {
      element.target?.markNeedsBuild();
    }
  }
}

T? inject<T>(BuildContext context, Symbol key) {
  final (value, found) = _lookupValueAndTrack<T>(context, key);
  if (found) return value;

  final target = _targets[context]?[key]?.target;
  if (target != null) {
    final (value, found) =
        _lookupValueAndTrack<T>(target, key, context as Element);
    if (found) return value;
  }

  T? inner;
  context.visitAncestorElements((element) {
    final (value, found) =
        _lookupValueAndTrack<T>(element, key, context as Element);
    if (found) {
      inner = value;
      return false;
    }

    return true;
  });

  return inner;
}

(T?, bool) _lookupValueAndTrack<T>(BuildContext context, Symbol key,
    [Element? element]) {
  final store = _refs[context];
  if (store != null && store.values.containsKey(key)) {
    if (element != null) {
      final elements = store.elements[key] ??= [];
      if (elements.every((e) => e.target != element)) {
        elements.add(WeakReference(element));
      }

      final targets = _targets[element] ??= {};
      targets[key] = WeakReference(context as Element);
    }

    final value = store.values[key];
    if (value is T?) {
      return (value, true);
    }
  }

  return (null, false);
}
