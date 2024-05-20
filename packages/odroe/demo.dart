class Node {
  Node? parent;
  final children = <Node>[];
}

Node? evalNode;
int uid = 0;

createNode(void Function() def) {
  def();
}

main() {
  createNode(() {});
  createNode(() {
    createNode(() {
      createNode(() {});
      createNode(() {});
    });
  });
}
