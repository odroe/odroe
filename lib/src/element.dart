import 'package:flutter/widgets.dart';

import 'widget.dart';

abstract final class OdroeElement implements Element {}

final class OdroeElementImpl extends ComponentElement implements OdroeElement {
  OdroeElementImpl(OdroeWidget super.widget);

  @override
  Widget build() {
    // TODO: implement build
    throw UnimplementedError();
  }
}
