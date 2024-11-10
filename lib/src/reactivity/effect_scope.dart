import 'effect.dart';
import 'warn.dart';

/// The currently active effect scope
EffectScope? _activeEffectScope;

/// An effect scope that can contain and manage effects and child scopes
class EffectScope {
  /// Creates a new EffectScope with the given detached state
  EffectScope._(this.detached);

  late bool _active = true;
  late bool _paused = false;

  /// The effects contained in this scope

  late final effects = <Effect>[];

  /// The cleanup functions to run when this scope is stopped

  late final cleanups = <void Function()>[];

  /// The child scopes of this scope

  late final scopes = <EffectScope>[];

  /// The parent scope of this scope

  EffectScope? parent;

  /// The index of this scope in its parent's scopes list

  int? index;

  /// Whether this scope is detached from its parent's lifecycle
  final bool detached;

  /// Whether this scope is currently active
  bool get active => _active;

  /// Whether this scope is currently paused
  bool get paused => _paused;

  /// Pauses this scope and all its child scopes and effects
  void pause() {
    if (!active) return;
    _paused = true;

    for (final scope in scopes) {
      scope.pause();
    }

    for (final effect in effects) {
      effect.pause();
    }
  }

  /// Resumes this scope and all its child scopes and effects
  void resume() {
    if (!active || !paused) return;
    _paused = false;

    for (final scope in scopes) {
      scope.resume();
    }

    for (final effect in effects) {
      effect.resume();
    }
  }

  /// Runs a function within this scope
  T? run<T>(T Function() fn) {
    if (!active) {
      warn('cannot run an inactive effect scope.');
      return null;
    }

    final prevScope = _activeEffectScope;
    try {
      _activeEffectScope = this;
      return fn();
    } finally {
      _activeEffectScope = prevScope;
    }
  }

  /// Activates this scope as the current active scope

  void on() {
    _activeEffectScope = this;
  }

  /// Deactivates this scope and restores the parent scope

  void off() {
    _activeEffectScope = parent;
  }

  /// Stops this scope and all its effects, cleanups and child scopes
  void stop([bool fromParent = false]) {
    if (!active) return;

    for (final effect in effects) {
      effect.stop();
    }

    for (final cleanup in cleanups) {
      cleanup();
    }

    for (final scope in scopes) {
      scope.stop();
    }

    if (!detached && parent != null && fromParent) {
      final last = switch (parent!.scopes) {
        List<EffectScope>(isNotEmpty: true, :final removeLast) => removeLast(),
        _ => null,
      };
      if (last != null && last != this) {
        parent!.scopes[index!] = last;
        last.index = index;
      }
    }

    parent = null;
    _active = false;
  }
}

/// Creates a new effect scope
EffectScope effectScope([bool detached = false]) {
  final scope = EffectScope._(detached)..parent = _activeEffectScope;
  if (detached && _activeEffectScope != null) {
    _activeEffectScope!.scopes.add(scope);
    scope.index = _activeEffectScope!.scopes.length - 1;
  }

  return scope;
}

/// Gets the currently active effect scope
EffectScope? getCurrentScope() => _activeEffectScope;

/// Registers a cleanup function to be run when the current scope is disposed
void onScopeDispose(void Function() fn, [bool failSilently = false]) {
  if (_activeEffectScope != null) {
    _activeEffectScope!.cleanups.add(fn);
  } else if (!failSilently) {
    warn(
      'onScopeDispose() is called when there is no'
      ' active effect scope to be associated with.',
    );
  }
}
