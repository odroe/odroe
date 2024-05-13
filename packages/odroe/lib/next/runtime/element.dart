import 'package:flutter/widgets.dart' as widgets;
import 'component.dart';
import 'lifecycle.dart';

abstract interface class Element {
  Owner get owner;
  Component get component;
}

/// Internal, [Element] impl.
class ElementImpl implements Element {
  ElementImpl(this.component);

  @override
  final Component component;

  @override
  late final Owner owner;
}

abstract interface class Owner implements Lifecycle {
  Element get element;
  int get depth;
  Owner? prev;
  Owner? next;
  Owner get root;
  widgets.Widget render();
}

Owner? evalOwner;
int depth = 0;

/// Due to the issue of language call order, deep algorithms invert numbers to ensure that they are always positive
Owner? findDepthOwner() {
  final root = evalOwner?.root;
  if (root == null) return null;

  Owner owner = root;
  while (owner.depth != depth) {
    if (owner.depth > depth) {
      throw StateError('Owner tree disorder');
    } else if (owner.next == null) {
      return null;
    }

    owner = owner.next!;
  }

  return owner;
}

/// Internal, Owner impl
class OwnerImpl implements Owner {
  OwnerImpl(this.element, this.depth);

  @override
  final Element element;

  @override
  Owner? next;

  @override
  Owner? prev;

  @override
  Owner get root => prev != null ? prev!.root : this;

  @override
  final int depth;

  @override
  void mount() {
    prev?.mount();
  }

  @override
  void unmount() {
    next?.unmount();
  }

  @override
  void update() {
    // TODO
  }

  @override
  widgets.Widget render() {
    if (prev != null) {
      return prev!.render();
    }
    // TODO: implement render, 目前没有自绘制组件，fire 和 veversal 会重写！
    throw UnimplementedError('$depth');
  }
}
