import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'internal/context_scope.dart';
import 'internal/widget_effect.dart';

/// Runs an effect in the context of a Flutter widget.
///
/// This function creates an [oref.EffectRunner] that executes the given [runner]
/// function within the specified [context]. It ensures proper initialization of
/// widget effects and handles tracking and scoping.
///
/// Parameters:
/// - [context]: The BuildContext in which the effect is running.
/// - [runner]: A function that defines the effect to be run.
/// - [scheduler]: An optional function to schedule the effect's execution.
/// - [onStop]: An optional function to be called when the effect stops.
///
/// Returns:
/// An [oref.EffectRunner<T>] instance that can be used to control the effect.
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
