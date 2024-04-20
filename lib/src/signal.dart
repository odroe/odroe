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
  /// Set the value if the Signal.
  void set(T value);
}

/// A Signal which is a formula based on other Signals.
abstract interface class Computed<T> implements Signal<T> {}
