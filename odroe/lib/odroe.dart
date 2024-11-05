import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:odroe/runs.dart';

OdroeElement? currentElement;
void Function() setCurrentElement(OdroeElement element) {
  final prev = currentElement;
  currentElement = element;
  return () => currentElement = prev;
}

class OdroeElement extends ComponentElement {
  OdroeElement(OdroeWidget super.widget);

  @override
  OdroeWidget get widget {
    assert(super.widget is OdroeWidget);
    return super.widget as OdroeWidget;
  }

  @override
  Widget build() {
    final reset = setCurrentElement(this);
    try {
      return widget.build();
    } finally {
      reset();
    }
  }
}

abstract class OdroeWidget extends Widget {
  const OdroeWidget({super.key});

  @nonVirtual
  @override
  OdroeElement createElement() {
    return OdroeElement(this);
  }

  @protected
  Widget build();
}

T $state<T>(T value) {
  return value;
}

class Counter extends OdroeWidget {
  const Counter({super.key});

  @override
  Widget build() {
    var count = $state(0);

    return TextButton(
      onPressed: () {},
      child: Text('Count: $count'),
    );
  }
}

@Component()
counter({String? name}) {
  var count = $state(0);

  return Text('Count: $count');
}
