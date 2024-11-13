import 'package:flutter/widgets.dart';
import 'framework.dart';

BuildContext useContext() {
  assert(currentElement != null);
  return currentElement!;
}
