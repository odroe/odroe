import '../types/private.dart' as private;

class Node implements private.Node {
  Node(this.subscriber, this.dependent) : version = dependent.version;

  @override
  int version;

  @override
  final private.Dependent dependent;

  @override
  final private.Subscriber subscriber;

  @override
  late final List<private.Node> dependents = [];

  @override
  late final List<private.Subscriber> subscribers = [];
}
