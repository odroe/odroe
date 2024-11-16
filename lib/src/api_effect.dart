import 'framework.dart';
import 'oncecall.dart';
import 'reactivity/effect_impl.dart';
import 'reactivity/effect_runner_impl.dart';
import 'reactivity/flags.dart';
import 'reactivity/types.dart';
import 'scheduler.dart';

abstract final class EffectAPI {
  EffectRunner<T> call<T>(T Function() fn,
      {void Function()? onStop, bool? allowRecurse});
  EffectRunner<T> pre<T>(T Function() fn,
      {void Function()? onStop, bool? allowRecurse});
  EffectRunner<T> post<T>(T Function() fn,
      {void Function()? onStop, bool? allowRecurse});
}

final class _EffectAPI implements EffectAPI {
  const _EffectAPI();

  @override
  EffectRunner<T> call<T>(T Function() fn,
      {void Function()? onStop, bool? allowRecurse}) {
    return oncecall(() {
      return oncecall(() {
        final effect =
            createEffect(fn, onStop: onStop, allowRecurse: allowRecurse);
        final runner = EffectRunnerImpl(effect.run(), effect);
        final job = SchedulerJob(
            currentElement?.id ?? double.infinity, createJobFn(runner));
        effect.scheduler = () => queueJob(job);

        return runner;
      });
    });
  }

  @override
  EffectRunner<T> pre<T>(T Function() fn,
      {void Function()? onStop, bool? allowRecurse}) {
    return oncecall(() {
      final effect =
          createEffect(fn, onStop: onStop, allowRecurse: allowRecurse);
      final runner = EffectRunnerImpl(effect.run(), effect);
      final job = SchedulerJob(-1, createJobFn(runner));
      effect.scheduler = () => queueJob(job);

      return runner;
    });
  }

  @override
  EffectRunner<T> post<T>(T Function() fn,
      {void Function()? onStop, bool? allowRecurse}) {
    return oncecall(() {
      final effect =
          createEffect(fn, onStop: onStop, allowRecurse: allowRecurse);
      final runner = EffectRunnerImpl(effect.run(), effect);
      final job = SchedulerJob(double.infinity, createJobFn(runner));
      effect.scheduler = () => queuePostJob(job);

      return runner;
    });
  }

  EffectImpl<T> createEffect<T>(T Function() fn,
      {void Function()? onStop, bool? allowRecurse}) {
    final effect = EffectImpl(fn, onStop: onStop);
    if (allowRecurse == true) {
      effect.flags |= Flags.allowRecurse;
    }

    return effect;
  }

  void Function() createJobFn<T>(EffectRunner<T> runner) {
    return () {
      if (runner.effect.dirty) runner();
    };
  }
}

const EffectAPI effect = _EffectAPI();
