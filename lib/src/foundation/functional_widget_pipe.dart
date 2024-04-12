import 'package:flutter/widgets.dart';

abstract interface class FunctionalWidgetPipe {
  Widget operator |(WidgetBuilder builder);
  FunctionalWidgetPipe operator +(Key key);
}
