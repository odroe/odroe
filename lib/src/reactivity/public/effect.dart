import '../_internal/effect_impl.dart';
import '../_internal/effect_runner_impl.dart';
import '../_internal/flags.dart';
import '../_internal/subscriber.dart';
import '../_internal/warn.dart';
import '../types.dart';

EffectRunner<T> effect<T>(
  T Function() fn, {
  void Function()? scheduler,
  void Function()? onStop,
  bool? allowRecurse,
}) {
  final effect = EffectImpl(fn);

  try {
    if (allowRecurse == true) {
      effect.flags |= Flags.allowRecurse;
    }
    effect.run();
  } catch (e) {
    effect.stop();
    rethrow;
  }

  return EffectRunnerImpl(effect);
}

void onEffectCleanup(void Function() fn, [bool failSilently = false]) {
  if (activeSub is! EffectImpl && !failSilently) {
    warn('onEffectCleanup() was called when there was no'
        ' active effect to associate with.');
    return;
  }

  final effect = activeSub as EffectImpl;
  final cleanup = switch (effect.cleanup) {
    void Function() prev => () {
        prev();
        fn();
      },
    _ => fn,
  };
  effect.cleanup = cleanup;
}
