import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

abstract base class SetupElement extends Element {
  SetupElement(SetupWidget super.widget);
}

abstract class SetupWidget extends Widget {
  @literal
  const SetupWidget({super.key});

  @override
  @nonVirtual
  SetupElement createElement() {
    ComponentElement;
    return _SetupElement(this);
  }
}

final class _SetupElement extends Element implements SetupElement {
  _SetupElement(super.widget) {
    // TODO, call setup
  }

  @override
  bool debugDoingBuild = false;

  @override
  Element? renderObjectAttachingChild;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    assert(renderObjectAttachingChild == null);
    rebuild();
    assert(renderObjectAttachingChild != null);
  }
}
