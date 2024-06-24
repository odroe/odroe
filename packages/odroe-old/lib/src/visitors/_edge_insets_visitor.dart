import 'package:flutter/widgets.dart';

import '../style.dart';
import 'style_visitor.dart';

abstract class EdgeInsetsVisitor implements StyleVisitor {
  const EdgeInsetsVisitor();

  EdgeInsetsGeometry? getEdgeInsets(Style style);

  @override
  Widget? visit(Style style, [Widget? widget]) {
    final edgeInsets = getEdgeInsets(style);
    if (edgeInsets == null) {
      return widget;
    }

    return Padding(
      padding: edgeInsets,
      child: widget,
    );
  }
}
