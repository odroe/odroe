import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'context_scope.dart';
import 'widget_effect.dart';

oref.Derived<T> derived<T>(BuildContext context, T Function() compute) {
  ensureInitializedWidgetEffect(context);
  final scope = getContextScope(context);

  scope.on();
  try {
    return oncecall(context, () => oref.derived(compute));
  } finally {
    scope.off();
  }
}
