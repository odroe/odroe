import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;
import 'package:oref_flutter/src/widget_effect.dart';

import 'context_scope.dart';

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
