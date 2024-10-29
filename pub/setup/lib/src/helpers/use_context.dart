import 'package:flutter/widgets.dart';

import '../global.dart';

/// Returns the current [BuildContext] from the widget.
///
/// This hook requires that [currentElement] is not null when called.
///
/// Throws an assertion error if [currentElement] is null.
BuildContext useContext() {
  assert(currentElement != null);
  return currentElement!;
}
