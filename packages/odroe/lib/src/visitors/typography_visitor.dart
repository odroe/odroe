import 'package:flutter/widgets.dart';

import '../style_sheet.dart';
import 'style_sheet_visitor.dart';

class TypographyVisitor implements StyleSheetVisitor {
  @override
  Widget visit(StyleSheet style, Widget widget) {
    return DefaultTextStyle.merge(
      style: TextStyle(
        package: style.package,
        fontFamily: style.fontFamily,
      ),
      child: widget,
    );
  }
}
