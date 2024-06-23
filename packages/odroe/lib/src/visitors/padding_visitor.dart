import 'package:flutter/widgets.dart';

import '../style.dart';
import '_edge_insets_visitor.dart';

class PaddingVisitor extends EdgeInsetsVisitor {
  const PaddingVisitor();

  @override
  EdgeInsetsGeometry? getEdgeInsets(Style style) => style.padding;
}
