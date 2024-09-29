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

/// Provides a value associated with a key in the given BuildContext.
///
/// This function is used to store a value of type [T] associated with a [key]
/// in the context of a specific widget. If the value has changed, it triggers
/// a rebuild of dependent widgets.
///
/// Parameters:
/// - [context]: The BuildContext in which to provide the value.
/// - [key]: A Symbol used as the identifier for the provided value.
/// - [value]: The value to be provided.
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

/// Injects a value associated with a key from the widget tree.
///
/// This function attempts to retrieve a value of type [T] associated with the
/// given [key]. It searches the widget tree upwards, starting from the given
/// [context], until it finds a matching value or reaches the root.
///
/// Parameters:
/// - [context]: The BuildContext from which to start the search.
/// - [key]: A Symbol used as the identifier for the value to be injected.
///
/// Returns:
/// The injected value of type [T], or null if not found.
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
