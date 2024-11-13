import 'package:meta/meta.dart';
import 'package:flutter/widgets.dart';

abstract class OdroeWidget extends Widget {
  const OdroeWidget({super.key});

  @protected
  @factory
  Widget build();

  @nonVirtual
  @override
  createElement() => OdroeElement(this);
}

class OdroeElement extends Element {
  OdroeElement(OdroeWidget super.widget);

  @override
  // TODO: implement debugDoingBuild
  bool get debugDoingBuild => throw UnimplementedError();
}
