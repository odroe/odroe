import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'internal/context_scope.dart';
import 'internal/widget_effect.dart';

/// Creates a new scope for effects.
///
/// This function creates a new [oref.Scope] and ensures that the widget effect
/// is properly initialized in the given [context]. It also manages the context
/// scope's lifecycle.
///
/// [context] - The BuildContext in which to create the scope.
/// [detached] - Whether the scope should be detached from its parent. Defaults to false.
///
/// Returns an [oref.Scope] instance.
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
