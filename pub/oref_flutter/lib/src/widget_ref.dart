import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'widget_effect.dart';

oref.Ref<T> toWidgetRef<T extends Widget>(BuildContext context, T widget) {
  ensureInitializedWidgetEffect(context);

  final widgetRef = oncecall(context, () => oref.ref(widget));
  if (context.mounted && !Widget.canUpdate(context.widget, widget)) {
    widgetRef.value = widget;
  }

  return oncecall(context, () => oref.derived(() => widgetRef.value));
}
