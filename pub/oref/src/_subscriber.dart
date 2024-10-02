import '_depend.dart';
import '_flags.dart';

Subscriber? evalSubscriber;

abstract interface class Subscriber {
  late Depend? head;
  late Depend? tail;
  late Subscriber? next;
  abstract Flags flags;
  void notify();
}
