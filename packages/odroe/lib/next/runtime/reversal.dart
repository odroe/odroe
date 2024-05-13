import 'package:flutter/widgets.dart' as widgets;

import 'element.dart';

widgets.Widget reversal(Element element) {
  return ReversalWidget(element);
}

class ReversalWidget extends widgets.Widget {
  const ReversalWidget(this.element, {super.key});

  final Element element;

  @override
  widgets.Element createElement() => ReversalElement(this);
}

class ReversalElement extends widgets.ComponentElement {
  ReversalElement(ReversalWidget super.widget);

  @override
  ReversalWidget get widget => super.widget as ReversalWidget;

  @override
  widgets.Widget build() {
    return widget.element.owner.render();
  }
}
