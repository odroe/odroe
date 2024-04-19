import 'source.dart';
import 'subscription.dart';
import 'types.dart';

class _Writeable<T> implements Writeable<T>, CurrentSource<T> {
  _Writeable(this.source, [this.notifier]);

  final StartStopNotifier<T>? notifier;
  late Unsubscriber? cleanup;

  @override
  T source;

  Subscription<T>? subscription;

  @override
  void set(T value) {
    if (source == value) return;

    source = value;
    subscription?.notice(source);
  }

  @override
  Unsubscriber subscribe(Subscriber<T> subscriber) {
    final subscription = Subscription(subscriber)..pre = this.subscription;
    void unsubscriber() {
      subscription.pre?.next = subscription.next;
      if (subscription.pre == null) {
        cleanup?.call();
      }
    }

    if (this.subscription == null) {
      this.subscription = subscription;

      final props = (set: set, update: update);
      cleanup = notifier?.call(props);

      return unsubscriber;
    }

    this.subscription?.last.next = subscription;
    return unsubscriber;
  }

  @override
  void update(Updater<T> updater) => set(updater(source));
}

Writeable<T> writeable<T>(T value, [StartStopNotifier<T>? start]) =>
    _Writeable(value, start);
