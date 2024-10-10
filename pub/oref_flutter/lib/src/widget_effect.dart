// ignore_for_file: implementation_imports

import 'package:_octr/_octr.dart';
import 'package:flutter/widgets.dart';
import 'package:oref/src/impls/effect.dart' as impl;
import 'package:oref/src/impls/flags.dart' as impl;
import 'package:oref/src/impls/sub.dart' as impl;
import 'package:oref/src/impls/global.dart' as impl;

import 'context_scope.dart';

final _memorized = findOrCreateExpando<impl.Effect>();
void _noop() {}

impl.Effect ensureInitializedWidgetEffect(BuildContext context) {
  final effect = _memorized[context];
  if (effect != null) return effect;

  final scope = getContextScope(context);
  scope.on();

  try {
    late final impl.Effect<void> effect;
    final prevActiveSub = impl.activeSub;
    final prevShouldTrack = impl.shouldTrack;

    void scheduler() {
      impl.cleanupDeps(effect);
      impl.activeSub = prevActiveSub;
      impl.shouldTrack = prevShouldTrack;
      effect.flags &= ~impl.Flags.running;

      if (context.mounted && effect.dirty) {
        (context as Element).markNeedsBuild();
      }
    }

    effect = impl.Effect(_noop, scheduler: scheduler);
    effect.flags |= impl.Flags.allowRecurse | impl.Flags.running;
    impl.prepareDeps(effect);
    impl.activeSub = effect;
    impl.shouldTrack = true;

    _memorized[context] = effect;

    return effect;
  } finally {
    scope.off();
  }
}
