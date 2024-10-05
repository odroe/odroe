/// Represents a reactive reference to a value of type T.
abstract interface class Ref<T> {
  /// Gets the current value of the reference.
  T get value;

  /// Sets a new value for the reference.
  set value(T newValue);
}

/// Represents a derived value that depends on other reactive references.
abstract interface class Derived<T> extends Ref<T> {}

/// Represents a scope for managing reactive effects and computations.
abstract interface class Scope {
  /// Indicates whether this scope is detached from its parent.
  bool get detached;

  /// Indicates whether this scope is currently active.
  bool get active;

  /// Pauses all effects within this scope.
  void pause();

  /// Resumes all paused effects within this scope.
  void resume();

  /// Stops all effects within this scope.
  ///
  /// [fromParent] indicates whether the stop was initiated by a parent scope.
  void stop([bool fromParent = false]);

  /// Runs a function within this scope and returns its result.
  ///
  /// [runner] is the function to be executed within the scope.
  T? run<T>(T Function() runner);
}

/// Represents a reactive effect that automatically tracks and responds to changes in reactive references.
abstract interface class Effect<T> {
  /// Indicates whether the effect is dirty and needs to be re-run.
  bool get dirty;

  /// A custom scheduler function for controlling when the effect should run.
  void Function()? get scheduler;

  /// A function to be called when the effect is stopped.
  void Function()? get onStop;

  /// Runs the effect and returns its result.
  T run();

  /// Stops the effect from running.
  void stop();

  /// Pauses the effect, preventing it from running until resumed.
  void pause();

  /// Resumes a paused effect, allowing it to run again.
  void resume();

  /// Manually triggers the effect to run, regardless of its current state.
  void trigger();
}

/// Represents a runner for reactive effects.
///
/// This interface defines the structure for objects that can execute effects
/// and retrieve the associated [Effect] object.
abstract interface class EffectRunner<T> {
  /// Gets the [Effect] associated with this runner.
  Effect<T> get effect;

  /// Executes the effect and returns its result.
  ///
  /// This method is callable, allowing the [EffectRunner] to be used as a function.
  ///
  /// Also -> [Effect.run]
  T call();
}
