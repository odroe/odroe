import 'package:flutter/widgets.dart';

import '../../style_sheet.dart';
import '../style_sheet_visitor.dart';

class SizeVisitor implements StyleSheetVisitor {
  const SizeVisitor();

  @override
  Widget visit(StyleSheet style, Widget widget) {
    if (style.width == null && style.height == null) {
      return widget;
    }

    return SizedBox(
      width: style.width,
      height: style.height,
      child: widget,
    );
  }
}
