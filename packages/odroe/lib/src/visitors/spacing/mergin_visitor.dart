import 'package:flutter/widgets.dart';

import '../../style_sheet.dart';
import '../style_sheet_visitor.dart';
import '_create_edge_insets.dart';

class MerginVisitor implements StyleSheetVisitor {
  const MerginVisitor();

  @override
  Widget visit(StyleSheet style, Widget widget) {
    return Padding(
      padding: createEdgeInsets(
        basic: style.mergin,
        top: style.merginTop,
        right: style.merginRight,
        bottom: style.merginBottom,
        left: style.merginLeft,
      ),
      child: widget,
    );
  }
}
