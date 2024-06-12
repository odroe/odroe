import 'package:flutter/widgets.dart';
import 'package:odroe/src/style_sheet.dart';

import '../style_sheet_visitor.dart';
import '_create_edge_insets.dart';

class PaddingVisitor implements StyleSheetVisitor {
  const PaddingVisitor();

  @override
  Widget visit(StyleSheet style, Widget widget) {
    return Padding(
      padding: createEdgeInsets(
        basic: style.padding,
        top: style.paddingTop,
        right: style.paddingRight,
        bottom: style.paddingBottom,
        left: style.paddingLeft,
      ),
      child: widget,
    );
  }
}
