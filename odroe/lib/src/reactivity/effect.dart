import 'package:odroe/src/reactivity/corss_link.dart';

import 'debugger.dart';
import 'subscriber.dart';

bool shouldTrack = true;
final _trackStack = <bool>[];

/// Temporarily pauses tracking.
void pauseTracking() {
  _trackStack.add(shouldTrack);
  shouldTrack = false;
}

/// Re-enables tracking.
void enableTracking() {
  _trackStack.add(shouldTrack);
  shouldTrack = true;
}

/// Resets the previous global tracking state.
void resetTracking() {
  try {
    shouldTrack = _trackStack.removeLast();
  } catch (_) {
    shouldTrack = true;
  }
}

abstract interface class ReactiveEffectOptions implements DebuggerOptions {
  @override
  void Function(DebuggerEvent event)? onTrack;

  @override
  void Function(DebuggerEvent event)? onTrigger;

  abstract bool allowRecurse;
  void Function()? scheduler;
  void Function()? onStop;
}

final class ReactiveEffectRunner<T> {
  const ReactiveEffectRunner._(this._innerEffect);
  final ReactiveEffect<T> _innerEffect;

  ReactiveEffect<T> get effect => _innerEffect;

  T call() => effect.run();
}

final class ReactiveEffect<T> implements Subscriber, ReactiveEffectOptions {
  @override
  CrossLink? depsHead;

  @override
  CrossLink? depsTail;

  @override
  int flags;

  @override
  Subscriber? next;

  @override
  bool allowRecurse;

  @override
  void Function()? onStop;

  @override
  void Function(DebuggerEvent event)? onTrack;

  @override
  void Function(DebuggerEvent event)? onTrigger;

  @override
  void Function()? scheduler;

  @override
  void notify() {
    // TODO: implement notify
  }
}
