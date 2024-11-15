import 'package:flutter/widgets.dart';

import 'framework.dart';

BuildContext useContext() {
  assert(currentElement is BuildContext);
  return currentElement!;
}
