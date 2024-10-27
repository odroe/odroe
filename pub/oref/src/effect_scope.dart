import 'flags.dart';
import 'warn.dart';

EffectScopeImpl? _currentEffectScope;
EffectScopeImpl? getCurrentEffectScope() => _currentEffectScope;
void Function() setCurrentEffectScope(EffectScopeImpl effectScope) {
  final prevEffectScope = _currentEffectScope;
  _currentEffectScope = effectScope;
  return () => _currentEffectScope = prevEffectScope;
}

abstract final class EffectScope {
  abstract final bool detached;
  bool get active;
  bool get paused;
  void on();
  void off();
  void pause();
  void resume();
  void stop();
  T? run<T>(T Function() _);
}

final class EffectScopeImpl implements EffectScope {
  EffectScopeImpl({this.detached = false})
      : flags = Flags.active,
        parent = getCurrentEffectScope() {
    if (!detached && parent != null) {
      parent!.children.add(this);
    }
  }

  int flags;
  EffectScopeImpl? parent;

  late final children = <EffectScopeImpl>[];
  // late final effects = <Effect>[];

  @override
  final bool detached;

  @override
  bool get active => flags & Flags.active != 0;

  @override
  bool get paused => flags & Flags.paused != 0;

  @override
  void off() {
    _currentEffectScope = parent;
  }

  @override
  void on() {
    _currentEffectScope = this;
  }

  @override
  void pause() {
    if (!active || paused) return;

    flags |= Flags.paused;
    for (final scope in children) {
      scope.pause();
    }

    // TODO effect
  }

  @override
  void resume() {
    if (!active || !paused) return;

    flags &= ~Flags.paused;
    for (final scope in children) {
      scope.resume();
    }

    // TODO: effect
  }

  @override
  void stop() {
    // TODO: implement stop
  }

  @override
  T? run<T>(T Function() runner) {
    if (!active) {
      warn('Cannot run an inactive effect scope.');
      return null;
    }

    final reset = setCurrentEffectScope(this);
    try {
      return runner();
    } finally {
      reset();
    }
  }
}
