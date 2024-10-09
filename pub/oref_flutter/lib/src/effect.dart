import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'context_scope.dart';

oref.EffectRunner<T> effect<T>(
  BuildContext context,
  T Function() runner, {
  void Function()? scheduler,
  void Function()? onStop,
}) {
  final scope = getContextScope(context);

  scope.on();

  try {
    return oncecall(
      context,
      () => scope.run(
        () => oref.effect(runner, scheduler: scheduler, onStop: onStop),
      )!,
    );
  } finally {
    scope.off();
  }
}
