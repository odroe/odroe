import 'package:flutter/widgets.dart';

abstract interface class StyleSheet {
  Widget wrap(Widget child, BuildContext context);
  StyleSheet merge(covariant StyleSheet sheet);
}

demo() {}
