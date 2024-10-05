import 'package:flutter/widgets.dart';

final _widgetEvalCount = Expando<int>();

Element findElement(Widget widget) {
  final root = WidgetsFlutterBinding.ensureInitialized().rootElement!;

  int evalCount = _widgetEvalCount[widget] ??= 0;

  Element? result;
  int currentCount = 0;

  void visitor(Element element) {
    if (result != null) return;

    if (Widget.canUpdate(element.widget, widget)) {
      if (currentCount == evalCount) {
        result = element;
        _widgetEvalCount[widget] = evalCount + 1;
        return;
      }
      currentCount++;
    }

    element.visitChildren(visitor);
  }

  visitor(root);

  if (result == null) {
    // 如果没找到，重置计数并再试一次
    _widgetEvalCount[widget] = 0;
    evalCount = 0;
    currentCount = 0;
    visitor(root);
  }

  if (result == null) {
    throw StateError(
        'Unable to find element for widget: ${widget.runtimeType}. This might indicate that the widget is not in the tree or all instances have been found.');
  }

  return result!;
}
