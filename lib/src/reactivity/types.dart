/// A reference that can be read.
abstract interface class Ref<T> {
  /// The current value of this reference.
  T get value;
}

/// A reference that can be both read and written to.
abstract interface class WritableRef<T> implements Ref<T> {
  /// Sets the value of this reference.
  set value(T _);
}

/// A reference whose value is computed from one or more other references.
abstract interface class ComputedRef<T> implements WritableRef<T> {}

abstract interface class ReadonlyRef<T, S extends Ref<T>> implements Ref<T> {}

abstract interface class Effect<T> {
  void Function()? get onStop;

  bool get dirty;

  void pause();
  void resume();
  void stop();
  T run();
}

abstract interface class EffectRunner<T> {
  Effect<T> get effect;
  T call();
}

abstract interface class EffectScope {
  bool get active;
  bool get paused;
  bool get detached;

  void on();
  void off();
  void pause();
  void resume();
  void stop();
  T? run<T>(T Function() _);
}
