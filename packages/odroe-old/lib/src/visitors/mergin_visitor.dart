import 'package:flutter/widgets.dart';

import '../style.dart';
import '_edge_insets_visitor.dart';

class MerginVisitor extends EdgeInsetsVisitor {
  const MerginVisitor();

  @override
  EdgeInsetsGeometry? getEdgeInsets(Style style) => style.mergin;
}
