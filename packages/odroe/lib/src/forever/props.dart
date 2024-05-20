import 'component.dart';
import 'next/reactivity/signals.dart';

class Node {
  late int uid;
  Component? component;
  Node? parent;
  final children = <Node>[];
  final props = <Signal>[];
  int counter = 0;
}

Node? evalNode;
int uid = 0;

void defineProps(Iterable props) {
  final child = evalNode;
  final parent = evalNode ?? Node()
    ..uid = uid++;
  final node = switch (parent.children.elementAtOrNull(parent.counter)) {
    Node node => node,
    _ => _createChildNode(parent)
  };
  for (final (index, prop) in props.indexed) {}
}

Node _createChildNode(Node parent) {
  final node = Node()..uid = uid++;

  parent.children.add(node);
  parent.counter++;

  return node;
}

List<Signal> props() {
  throw StateError('[odroe] Please use `defineProps` to define props.');
}
