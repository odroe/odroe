import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'context_scope.dart';
import 'widget_effect.dart';

oref.Scope createScope(BuildContext context, [bool detached = false]) {
  ensureInitializedWidgetEffect(context);
  final scope = getContextScope(context);
  scope.on();

  try {
    return oncecall(context, () => oref.createScope(detached));
  } finally {
    scope.off();
  }
}
