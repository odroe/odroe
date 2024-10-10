import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'internal/context_scope.dart';
import 'internal/widget_effect.dart';

oref.Derived<T> derived<T>(BuildContext context, T Function() getter) {
  ensureInitializedWidgetEffect(context);
  final scope = getContextScope(context);

  scope.on();
  try {
    return oncecall(context, () => oref.derived(getter));
  } finally {
    scope.off();
  }
}

extension FlutterGlobalDerivedUtils on oref.Derived<T> Function<T>(
    BuildContext, T Function()) {
  oref.Derived<T> writable<T>(
    BuildContext context,
    T Function(T? oldValue) getter,
    void Function(T newValue) setter,
  ) {
    ensureInitializedWidgetEffect(context);
    final scope = getContextScope(context);

    scope.on();
    try {
      return oncecall(context, () => oref.derived.writable(getter, setter));
    } finally {
      scope.off();
    }
  }

  oref.Derived<T> valuable<T>(
      BuildContext context, T Function(T? oldValue) getter) {
    ensureInitializedWidgetEffect(context);
    final scope = getContextScope(context);

    scope.on();
    try {
      return oncecall(context, () => oref.derived.valuable(getter));
    } finally {
      scope.off();
    }
  }
}
