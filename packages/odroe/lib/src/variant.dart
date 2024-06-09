import 'package:flutter/widgets.dart';

import 'style_sheet.dart';

abstract class Variant {
  const Variant(this.style);
  final StyleSheet style;

  bool when(BuildContext context);
}
