import '../types/private.dart' as private;
import 'utils.dart';

Scope? evalScope;

final class Scope implements private.Scope {
  Scope(this.detached) {
    parent = evalScope;
    if (!detached && evalScope != null) {
      evalScope!.scopes.add(this);
      index = evalScope!.scopes.length - 1;
    }
  }

  late bool paused = false;

  @override
  late int? index;

  @override
  final bool detached;

  @override
  late Scope? parent;

  @override
  late bool active = true;

  @override
  late final List<void Function()> cleanups = [];

  @override
  late final List<private.Scope> scopes = [];

  @override
  late final List<private.Effect> effects = [];

  @override
  void off() {
    evalScope = parent;
  }

  @override
  void on() {
    evalScope = this;
  }

  @override
  void pause() {
    if (!active) return;

    paused = true;
    for (final scope in scopes) {
      scope.pause();
    }
    for (final effect in effects) {
      effect.pause();
    }
  }

  @override
  void resume() {
    if (!active || !paused) return;
    paused = true;
    for (final scope in scopes) {
      scope.resume();
    }
    for (final effect in effects) {
      effect.resume();
    }
  }

  @override
  T? run<T>(T Function() runner) {
    if (active) {
      final prevScope = evalScope;
      try {
        evalScope = this;
        return runner();
      } finally {
        evalScope = prevScope;
      }
    } else if (dev) {
      warn('Cannot run effects outside of an active scope.');
    }

    return null;
  }

  @override
  void stop([bool fromParent = false]) {
    if (!active) return;

    // Stop all scoped effects.
    for (final effect in effects) {
      effect.stop();
    }

    // Run all cleanups.
    for (final cleanup in cleanups) {
      cleanup();
    }

    // Stop all child scopes.
    for (final scope in scopes) {
      scope.stop(true);
    }

    // Nested scopes are stopped by their parent scope.
    if (!detached && parent != null && !fromParent) {
      final last = switch (parent!.scopes) {
        List<private.Scope>(isEmpty: true) => null,
        _ => parent!.scopes.removeLast(),
      };
      if (last != null && last != this) {
        parent!.scopes[index!] = last;
        last.index = index;
      }
    }

    parent = null;
    active = false;
  }
}
