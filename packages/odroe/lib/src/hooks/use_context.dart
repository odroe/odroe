import 'package:flutter/widgets.dart';

import '../element.dart';

/// Returns a [BuildContext] by current setup-widget.
BuildContext useContext() {
  final context = evalElement;
  assert(context != null);

  return context!;
}
