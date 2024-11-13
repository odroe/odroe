import 'package:meta/meta.dart';
import 'package:flutter/widgets.dart';

import 'oncecall.dart';

abstract class OdroeWidget extends Widget {
  const OdroeWidget({super.key});

  @protected
  @factory
  Widget build();

  @nonVirtual
  @override
  createElement() => _OdroeElement(this);
}

_OdroeElement? _element;
// ignore: library_private_types_in_public_api
_OdroeElement? currentElement = _element;

// ignore: library_private_types_in_public_api
void Function() setCurrentElement(_OdroeElement element) {
  final prev = _element;
  _element = element;
  enableOncecall();

  return () {
    _element = prev;
    resetOncecall();
  };
}

class _OdroeElement extends ComponentElement with Oncecall {
  _OdroeElement(OdroeWidget super.widget) {
    final reset = setCurrentElement(this);
    try {
      widget.build();
    } finally {
      reset();
    }
  }

  @override
  OdroeWidget get widget => super.widget as OdroeWidget;

  @override
  late bool debugDoingBuild = false;
  late Widget built;

  @override
  Widget build() {
    final reset = setCurrentElement(this);
    try {
      print(1);
      return widget.build();
    } finally {
      reset();
    }
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    print(2);
    super.mount(parent, newSlot);
  }
}
