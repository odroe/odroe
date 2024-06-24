import 'package:flutter/widgets.dart';

import '../style.dart';
import 'style_visitor.dart';

class ConstraintsVisitor implements StyleVisitor {
  @override
  Widget? visit(Style style, [Widget? widget]) {
    if (style.constraints == null) return widget;

    return ConstrainedBox(
      constraints: style.constraints!,
      child: widget,
    );
  }
}
