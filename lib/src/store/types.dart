typedef Subscriber<T> = void Function(T value);
typedef Unsubscriber = void Function();
typedef Updater<T> = T Function(T value);
typedef StartStopNotifier<T> = Unsubscriber? Function(
    ({
      Subscriber<T> set,
      T Function() get,
      void Function(Updater<T> updater) update,
    }));

abstract interface class Readable<T> {
  /// Subscribe on value changes
  Unsubscriber subscribe(Subscriber<T> subscriber);
}

abstract interface class Writeable<T> implements Readable<T> {
  /// Set value and inform subscribers
  void set(T value);

  /// Update value using callback and inform subscribers.
  void update(Updater<T> updater);
}
