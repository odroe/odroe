import 'package:flutter/widgets.dart';

import '../style_sheet.dart';

abstract interface class StyleSheetVisitor {
  Widget visit(StyleSheet style, Widget widget);
}
