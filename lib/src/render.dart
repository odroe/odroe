import 'package:flutter/widgets.dart';

extension type const WidgetRender._(Widget Function() _) {
  Widget call() => _();
}

WidgetRender h(Widget Function() fn) => WidgetRender._(fn);
