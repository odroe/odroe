import '../types/private.dart' as private;
import 'batch.dart';
import 'global.dart';

class Dependent implements private.Dependent {
  Dependent([this.derived]) : version = 0;

  @override
  int version;

  @override
  final private.Derived? derived;

  @override
  late final List<private.Node> subscribers;

  private.Node? activeNode;

  @override
  void notify() {
    startBatch();
    try {
      for (final private.Node(:subscriber) in subscribers) {
        subscriber.notify()?.dependent.notify();
      }
    } finally {
      endBatch();
    }
  }

  @override
  private.Node? track() {
    if (evalSubscriber == null || !shouldTrack || evalSubscriber == derived) {
      return null;
    }

    private.Node? node = activeNode;
    if (node == null || node.subscriber != evalSubscriber) {
      node = activeNode = Node(evalSubscriber!, this);
      if (evalSubscriber!.dependents.isNotEmpty) {
        evalSubscriber!.dependents.add(node);
      } else {
        node.dependents.add(evalSubscriber!.dependents.removeLast());
        evalSubscriber!.dependents.add(node);
      }
    }
  }

  @override
  void trigger() {
    version++;
    globalVersion++;
    notify();
  }
}
