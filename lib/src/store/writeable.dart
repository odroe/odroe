import 'source.dart';
import 'types.dart';

class _Writeable<T> implements Writeable<T>, CurrentSource<T> {
  _Writeable(this.source, [this.start]);

  final StartStopNotifier<T>? start;
  final List<Subscriber<T>> subscribers = [];

  late Unsubscriber? stop;

  @override
  T source;

  @override
  void set(T value) {
    if (source == value) return;

    source = value;
    for (final subscriber in subscribers) {
      subscriber(source);
    }
  }

  @override
  Unsubscriber subscribe(Subscriber<T> subscriber) {
    subscribers.add(subscriber);

    if (subscribers.length == 1) {
      final props = (set: set, update: update);
      stop = start?.call(props);
    }

    void unsubscriber() {
      subscribers.remove(subscriber);
      if (subscribers.isEmpty) {
        stop?.call();
      }
    }

    return unsubscriber;
  }

  @override
  void update(Updater<T> updater) => set(updater(source));
}

/// Function that creates a store which has values that can be set from
/// 'outside' components. It gets created as an record with additional `set` and
/// `update` methods.
///
/// - `set`: is a method that takes one argument which is the value to be set.
/// The store value gets set to the value of the argument if the store value is
/// not already equal to it.
/// - `update`: is a method that takes one argument which is a callback. The
/// callback takes the existing store value as its argument and returns the new
/// value to be set to the store.
///
/// ```dart
/// final count = writeable(0);
///
/// count.subscribe((value) => print(value));
///
/// count.set(1); // Print 1
/// count.update((value) => value + 1); // Print 2
/// ```
Writeable<T> writeable<T>(T value, [StartStopNotifier<T>? start]) =>
    _Writeable(value, start);
