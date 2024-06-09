import 'package:flutter/widgets.dart';

import '../../style_sheet.dart';
import '../style_sheet_visitor.dart';

class ConstrainedSizeVisitor implements StyleSheetVisitor {
  @override
  Widget visit(StyleSheet style, Widget widget) {
    if ([style.maxWidth, style.maxHeight, style.minWidth, style.minHeight]
        .every((e) => e == null)) {
      return widget;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: style.maxWidth ?? double.infinity,
        maxHeight: style.maxHeight ?? double.infinity,
        minWidth: style.minWidth ?? 0.0,
        minHeight: style.minHeight ?? 0.0,
      ),
      child: widget,
    );
  }
}
