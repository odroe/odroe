import 'package:odroe/src/style_sheet.dart';

import 'pattern_style.dart';

class NamedStyle implements PatternStyle {
  const NamedStyle(String name, this.style) : pattern = name;

  @override
  final String pattern;
  final StyleSheet style;

  @override
  StyleSheet build(_) => style;
}
