import 'package:flutter/widgets.dart';

import '../element.dart';

/// Returns current widget build context rune.
///
/// In Odroe Setup Widget, we do not need to receive any parameters, but it is
/// compatible with Flutter Widgets, such as' Theme. of 'which requires the use
/// of BuildContext. At this point, you can use $context run to obtain it.
BuildContext $context() => SetupElement.current;
