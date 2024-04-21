/// Signal based-read interface.
///
/// @see [State]
/// @see [Computed]
abstract interface class Signal<T> {
  /// Returns a value of the signal.
  T get();
}

/// A read-write Signal.
abstract interface class State<T> implements Signal<T> {
  /// Set the value of the Signal.
  void set(T value);

  /// Update the value of the Signal.
  void update(T Function(T value) updater);
}

/// A Signal which is a formula based on other Signals.
abstract interface class Computed<T> implements Signal<T> {}
