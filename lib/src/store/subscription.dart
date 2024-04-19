import 'types.dart';

class Subscription<T> {
  Subscription(this.subscriber);

  final Subscriber<T> subscriber;
  Subscription<T>? next;

  void notice(T value) {
    Subscription<T>? current = this;
    while (current?.next != null) {
      current?.subscriber(value);
      current = current?.next;
    }
  }
}
