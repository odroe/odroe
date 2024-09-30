import 'package:flutter/widgets.dart';

import 'types.dart';

Ref<T> ref<T>(BuildContext context, T initialValue) {
  return _RefImpl<T>(initialValue, context);
}

class _RefImpl<T> implements Ref<T> {
  _RefImpl(this._value, this._context);

  T _value;
  final BuildContext _context;
  final List<WeakReference<Element>> _dependents = [];
  bool _isDirty = false;

  @override
  T get value {
    _trackDependency();
    return _value;
  }

  @override
  set value(T newValue) {
    if (_value != newValue) {
      _value = newValue;
      _isDirty = true;
      _notifyDependents();
    }
  }

  void _trackDependency() {
    final element = _context as Element;
    if (!_dependents.any((dep) => dep.target == element)) {
      _dependents.add(WeakReference(element));
    }
  }

  void _notifyDependents() {
    if (!_isDirty) return;

    _dependents.removeWhere((dep) => dep.target == null);
    for (final dep in _dependents) {
      dep.target?.markNeedsBuild();
    }
    _isDirty = false;
  }
}
