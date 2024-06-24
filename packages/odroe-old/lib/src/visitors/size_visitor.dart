import 'package:flutter/widgets.dart';

import '../style.dart';
import 'style_visitor.dart';

class SizeVisitor implements StyleVisitor {
  const SizeVisitor();

  @override
  Widget? visit(Style style, [Widget? widget]) {
    if (style.size == null) return widget;

    return SizedBox(
      width: style.size?.width,
      height: style.size?.height,
      child: widget,
    );
  }
}
