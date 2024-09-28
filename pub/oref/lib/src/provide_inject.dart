import 'package:flutter/widgets.dart';

import '_internal/has_changed.dart';

class _Store {
  final Widget widget;
  final values = <Symbol, Object?>{};
  final elements = <Symbol, List<WeakReference<Element>>>{};

  _Store(this.widget);
}

final _refs = Expando<_Store>();
final _targets = Expando<Map<Symbol, WeakReference<Element>>>();

void provide<T>(BuildContext context, Symbol key, T value) {
  var store = _refs[context] ??= _Store(context.widget);
  if (!Widget.canUpdate(store.widget, context.widget)) {
    store = _refs[context] = _Store(context.widget);
  }

  if (hasChanged(store.values[key], value)) {
    store.values[key] = value;
    store.elements[key]?.forEach((element) => element.target?.markNeedsBuild());
  }
}

T? inject<T>(BuildContext context, Symbol key) {
  final (v, f) = _lookupValueAndTrack<T>(context, key);
  if (f) return v;

  final target = _targets[context]?[key]?.target;
  if (target != null) {
    final (v, f) = _lookupValueAndTrack<T>(target, key, context as Element);
    if (f) return v;
  }

  T? value;
  context.visitAncestorElements((element) {
    final (v, f) = _lookupValueAndTrack<T>(element, key, context as Element);
    value = v;

    return !f;
  });

  return value;
}

(T?, bool) _lookupValueAndTrack<T>(BuildContext context, Symbol key,
    [Element? element]) {
  final store = _refs[context];
  if (store?.values.containsKey(key) ?? false) {
    if (element != null) {
      store!.elements.putIfAbsent(key, () => [])
        ..removeWhere((ref) => ref.target == null)
        ..add(WeakReference(element));

      (_targets[element] ??= {})[key] = WeakReference(context as Element);
    }

    return (store?.values[key] as T?, true);
  }

  return (null, false);
}
