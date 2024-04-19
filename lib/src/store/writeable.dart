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
      final props = (set: set, update: update, get: () => source);
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

Writeable<T> writeable<T>(T value, [StartStopNotifier<T>? start]) =>
    _Writeable(value, start);
