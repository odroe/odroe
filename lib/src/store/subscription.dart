import 'types.dart';

class Subscription<T> {
  Subscription(this.subscriber);

  final Subscriber<T> subscriber;

  Subscription<T>? pre;
  Subscription<T>? next;

  Subscription<T> get first {
    return switch (pre) {
      Subscription<T>(first: final first) => first,
      null => this,
    };
  }

  Subscription<T> get last {
    return switch (next) {
      Subscription<T>(last: final last) => last,
      null => this,
    };
  }

  void notice(T value) {
    Subscription<T>? current = first;
    while (current?.next != null) {
      current?.subscriber(value);
      current = current?.next;
    }
  }
}
