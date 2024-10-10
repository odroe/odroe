import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'internal/context_scope.dart';
import 'internal/widget_effect.dart';

oref.WatchHandle watch<T extends Record>(
  BuildContext context,
  T Function() compute,
  void Function(T value, T? oldValue) runner, {
  bool immediate = false,
  bool once = false,
}) {
  ensureInitializedWidgetEffect(context);
  final scope = getContextScope(context);
  scope.on();

  try {
    return oncecall(context,
        () => oref.watch<T>(compute, runner, immediate: immediate, once: once));
  } finally {
    scope.off();
  }
}
