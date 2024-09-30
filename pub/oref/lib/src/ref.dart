import 'package:flutter/widgets.dart';

import '_internal/has_changed.dart';
import 'types.dart';

final _refs = Expando<List<_Ref>>();
final _indices = Expando<int>();
Element? _evalElement;

/// A reactive reference system for Flutter.
///
/// This system allows for creating reactive references that automatically
/// track dependencies and trigger rebuilds when their values change.
///
/// Example:
///
/// ```dart
/// class CounterWidget extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     final count = ref(context, 0);
///
///     return Column(
///       children: [
///         Text('Count: ${count.value}'),
///         ElevatedButton(
///           onPressed: () => count.value++,
///           child: Text('Increment'),
///         ),
///       ],
///     );
///   }
/// }
/// ```
///
/// In this example, `ref` creates a reactive reference to an integer.
/// When the button is pressed, it increments the value, which automatically
/// triggers a rebuild of the widget, updating the displayed count.
Ref<T> ref<T>(BuildContext context, T initialValue) {
  final element = context as Element;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_indices[element] != 0) {
      _indices[element] = 0;
    }
  });

  final refs = _refs[element] ??= [];
  final index = _indices[element] ??= 0;
  final ref = refs.elementAtOrNull(index);

  if (ref != null && ref.innerValue is T) {
    _indices[element] = index + 1;
    return ref as Ref<T>;
  }

  final newRef = _Ref<T>(initialValue);

  if (index >= refs.length) {
    refs.add(newRef);
  } else {
    refs[index] = newRef;
  }

  _indices[element] = index + 1;
  _evalElement = element;

  return newRef;
}

class _Ref<T> implements Ref<T> {
  _Ref(this.innerValue);

  T innerValue;
  bool dirty = false;

  final List<WeakReference<Element>> dependents = [];

  @override
  T get value {
    track();

    return innerValue;
  }

  @override
  set value(T newValue) {
    if (!hasChanged(innerValue, newValue)) return;

    innerValue = newValue;
    dirty = true;

    trigger();
  }

  void track() {
    if (_evalElement == null) return;
    dependents.removeWhere((ref) => ref.target == null);

    // Check if the current element is already a dependent.
    if (dependents.every((ref) => ref.target != _evalElement)) {
      dependents.add(WeakReference(_evalElement!));
    }
  }

  void trigger() {
    if (!dirty) return;
    dependents.removeWhere((ref) => ref.target == null);

    // Trigger all dependents to rebuild.
    for (final ref in dependents) {
      ref.target?.markNeedsBuild();
    }
  }
}
