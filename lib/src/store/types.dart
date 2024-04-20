/// Store subscriber.
typedef Subscriber<T> = void Function(T value);

/// Store ubsubscriber.
typedef Unsubscriber = void Function();

/// Store uodater.
typedef Updater<T> = T Function(T value);

/// Store notifier.
typedef StartStopNotifier<T> = Unsubscriber? Function(
    ({
      Subscriber<T> set,
      void Function(Updater<T> updater) update,
    }));

/// Readable store.
abstract interface class Readable<T> {
  /// Subscribe on value changes
  Unsubscriber subscribe(Subscriber<T> subscriber);
}

/// Writeable store.
abstract interface class Writeable<T> implements Readable<T> {
  /// Set value and inform subscribers
  void set(T value);

  /// Update value using callback and inform subscribers.
  void update(Updater<T> updater);
}
