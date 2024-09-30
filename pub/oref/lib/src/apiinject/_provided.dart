import 'package:flutter/widgets.dart';

final provides = Expando<Map<Symbol, Provided>>();

class Provided<T> {
  Provided(this.value, [List<WeakReference<Element>>? dependents])
      : dependents = dependents ?? [];

  T value;
  final List<WeakReference<Element>> dependents;

  void track(Element element) {
    dependents.removeWhere((weakRef) => weakRef.target == null);
    if (dependents.every((weakRef) => weakRef.target != element)) {
      dependents.add(WeakReference(element));
    }
  }

  void trigger() {
    dependents.removeWhere((weakRef) => weakRef.target == null);
    for (final weakRef in dependents) {
      weakRef.target?.markNeedsBuild();
    }
  }
}
