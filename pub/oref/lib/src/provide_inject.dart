import 'package:flutter/widgets.dart';

import '_internal/has_changed.dart';

class _Provided<T> {
  _Provided(this.value);

  T value;
  late final List<WeakReference<Element>> dependents = [];

  void addDependent(Element element) {
    dependents.removeWhere((weakRef) => weakRef.target == null);
    if (dependents.every((weakRef) => weakRef.target != element)) {
      dependents.add(WeakReference(element));
    }
  }

  void notifyDependents() {
    dependents.removeWhere((weakRef) => weakRef.target == null);
    for (final weakRef in dependents) {
      weakRef.target?.markNeedsBuild();
    }
  }
}

final _providedValues = Expando<Map<Symbol, _Provided>>();
final _injectCache = Expando<Map<Symbol, WeakReference<Element>>>();

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
  final values = _providedValues[context] ??= {};
  final provided = values[key] as _Provided<T>?;

  if (provided == null || hasChanged(provided.value, value)) {
    if (provided == null) {
      values[key] = _Provided(value);
      return;
    }

    provided.value = value;
    provided.notifyDependents();
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
  final Element element = context as Element;

  // 检查缓存
  final cache = _injectCache[element] ??= {};
  final cachedAncestor = cache[key]?.target;
  if (cachedAncestor != null) {
    final values = _providedValues[cachedAncestor];
    if (values != null && values.containsKey(key)) {
      final provided = values[key] as _Provided<T>;
      provided.addDependent(element);
      return provided.value;
    }
  }

  // 如果缓存未命中，执行常规查找
  T? result;
  element.visitAncestorElements((Element ancestor) {
    final values = _providedValues[ancestor];
    if (values != null && values.containsKey(key)) {
      final provided = values[key] as _Provided<T>;
      provided.addDependent(element);
      result = provided.value;

      // 更新缓存
      cache[key] = WeakReference(ancestor);
      return false;
    }
    return true;
  });

  return result;
}
