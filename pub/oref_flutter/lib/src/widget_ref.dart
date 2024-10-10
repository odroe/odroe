import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'internal/widget_effect.dart';

/// Converts a widget to a widget reference.
///
/// This function takes a [BuildContext] and a widget of type [T] as input,
/// and returns an [oref.Ref<T>] that can be used to track changes to the widget.
///
/// The function ensures that the widget effect is initialized for the given context,
/// creates a reference to the widget, and updates it if necessary.
///
/// Parameters:
///   - [context]: The build context of the widget.
///   - [widget]: The widget to be converted to a reference.
oref.Derived<T> toWidgetRef<T extends Widget>(BuildContext context, T widget) {
  ensureInitializedWidgetEffect(context);

  final ref = oncecall(context, () => oref.derived(() => widget));
  if (context.mounted && !Widget.canUpdate(context.widget, widget)) {
    oref.triggerRef(ref);
  }

  return ref;
}
