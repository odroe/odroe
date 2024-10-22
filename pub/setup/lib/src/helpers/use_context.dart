import 'package:flutter/widgets.dart';

import '../global.dart';

BuildContext useContext() {
  assert(currentElement != null);
  return currentElement!;
}
