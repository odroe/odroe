import 'package:flutter/widgets.dart';

class SetupWidget extends Widget {
  const SetupWidget({super.key});

  @override
  Element createElement() => SetupElement(this);
}

class SetupElement extends Element {
  SetupElement(super.widget);

  @override
  bool get debugDoingBuild => throw UnimplementedError();

  @override
  void mount(Element? parent, Object? newSlot) {
    StatelessElement;

    // TODO: implement mount
    super.mount(parent, newSlot);
  }
}
