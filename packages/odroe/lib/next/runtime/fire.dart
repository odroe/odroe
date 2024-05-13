import 'package:flutter/widgets.dart' as widgets;

import 'component.dart';
import 'element.dart';

typedef FireMaker = widgets.Widget Function();

Element fire(FireMaker maker, {widgets.Key? key}) {
  final depthOwner = findDepthOwner();
  if (depthOwner != null) {
    if (depthOwner is FireOwner &&
        depthOwner.element.component.widget.key == key) {
      evalOwner = depthOwner;
      depth++;

      // TODO: Compare whether Props have been updated, and if so, notify the owner to rebuild
      return depthOwner.element;
    }

    depthOwner.destroy();
    evalOwner = depthOwner.prev;
    depthOwner.next = null;
  }

  final parent = evalOwner;
  final widget = FireWidget(maker, key: key);
  final component = FireComponent(widget);
  final element = FireElement(component);
  final owner = FireOwner(element, depth);

  owner.prev = parent;
  widget.owner = owner;
  evalOwner = owner;
  depth++;

  throw 1;
}

class FireComponent implements Component {
  FireComponent(this.widget);

  String? _displayName;

  @override
  String? get displayName => _displayName ?? widget.toStringShort();

  @override
  set displayName(String? name) => _displayName = name;

  final FireWidget widget;

  @override
  Element call(covariant void _) =>
      throw UnsupportedError('[odroe] fire component dont support call');
}

class FireElement extends ElementImpl {
  FireElement(FireComponent super.component);

  @override
  FireComponent get component => super.component as FireComponent;
}

class FireWidget extends widgets.Widget {
  // ignore: prefer_const_constructors_in_immutables
  FireWidget(this.maker, {super.key});

  final FireMaker maker;
  late final Owner owner;

  @override
  FireWidgetElement createElement() => FireWidgetElement(this);
}

class FireWidgetElement extends widgets.ComponentElement {
  FireWidgetElement(super.widget);

  @override
  FireWidget get widget => super.widget as FireWidget;

  late widgets.Widget cachedWidget;
  bool shouldRebuild = false;

  @override
  widgets.Widget build() {
    if (!shouldRebuild) return cachedWidget;

    cachedWidget = widget.maker();
    shouldRebuild = false;

    return cachedWidget;
  }

  @override
  markNeedsBuild() {
    shouldRebuild = true;
    super.markNeedsBuild();
  }

  @override
  rebuild({bool force = false}) {
    shouldRebuild = true;
    super.rebuild(force: force);
  }

  @override
  mount(widgets.Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    widget.owner.mount();
  }

  @override
  unmount() {
    super.unmount();
    widget.owner.unmount();
  }
}

class FireOwner extends OwnerImpl {
  FireOwner(FireElement super.element, super.depth);

  @override
  FireElement get element => super.element as FireElement;

  FireWidgetElement? flutterWidgetElement;

  @override
  update() {
    super.update();
    flutterWidgetElement?.markNeedsBuild();
  }
}
