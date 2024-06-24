import 'package:flutter/widgets.dart';

import '../style.dart';

abstract interface class StyleVisitor {
  Widget? visit(Style style, [Widget? widget]);
}
