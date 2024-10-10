import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'internal/widget_effect.dart';

oref.Ref<T> ref<T>(BuildContext context, T value) {
  ensureInitializedWidgetEffect(context);

  return oncecall(context, () => oref.ref(value));
}
