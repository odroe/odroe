import 'package:flutter/widgets.dart';

import 'element.dart';

class SetupWidget<Props> extends Widget with SetupSource<Props> {
  const SetupWidget(this.callback, {super.key, this.props});

  @override
  final SetupCallback callback;

  @override
  final Props? props;

  @override
  SetupElement<Props> createElement() => SetupElement<Props>(this);
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
Widget setup<T>(SetupCallback fn, {Key? key, T? props}) {
  final widget = SetupWidget<T>(fn, key: key, props: props);
  if (props != null) {
    print(widget == SetupWidget<T>(fn, key: key, props: props));
  }
  return SetupWidget<T>(fn, key: key, props: props);
}
