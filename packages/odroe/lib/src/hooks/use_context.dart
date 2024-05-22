import 'package:flutter/widgets.dart';

import '../element.dart';

BuildContext useContext() {
  final context = evalElement;
  assert(context != null);

  return context!;
}
