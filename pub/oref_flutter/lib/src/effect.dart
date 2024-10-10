import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'internal/context_scope.dart';
import 'internal/widget_effect.dart';

oref.EffectRunner<T> effect<T>(
  BuildContext context,
  T Function() runner, {
  void Function()? scheduler,
  void Function()? onStop,
}) {
  ensureInitializedWidgetEffect(context);

  final scope = getContextScope(context);
  scope.on();
  oref.pauseTracking();

  try {
    return oncecall(
      context,
      () => oref.effect(runner, scheduler: scheduler, onStop: onStop),
    );
  } finally {
    oref.resetTracking();
    scope.off();
  }
}
