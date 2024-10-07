import 'package:_octr/_octr.dart';
import 'package:flutter/widgets.dart';

final globalProvides = <Object, Provided>{};
final provides = findOrCreateExpando<Map<dynamic, Provided>>();

class Provided<T> {
  Provided(this.value, [List<WeakReference<Element>>? deps])
      : deps = deps ?? [];

  T value;
  final List<WeakReference<Element>> deps;

  void track(Element element) {
    deps.removeWhere((ref) => ref.target == null);
    if (deps.any((ref) => ref.target == element)) {
      return;
    }

    deps.add(WeakReference(element));
  }

  void trigger() {
    deps.removeWhere((ref) => ref.target == null);
    for (final ref in deps) {
      ref.target?.markNeedsBuild();
    }
  }
}
