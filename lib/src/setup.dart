import 'package:flutter/widgets.dart';

import '_internal/props_key.dart';
import 'element.dart';

class SetupWidget extends Widget {
  const SetupWidget(this.fn, {super.key});

  final SetupCallback fn;

  @override
  SetupElement createElement() => SetupElement(this, fn);
}

/// Functional wrapper for Setup Widget.
///
/// [setup] is used to wrap the setup function to create a functional widget:
///
/// ```dart
/// Widget app() => setup(() {
///   // The is setup body, create Runes and return widget.
///   ...
/// });
/// ```
Widget setup<T extends Object?>(SetupCallback fn, {Key? key, T? props}) {
  return SetupWidget(fn, key: key ?? (props != null ? PropsKey(props) : null));
}
