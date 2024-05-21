import 'package:flutter/widgets.dart';

import 'element.dart';
import 'key.dart';
import 'props.dart';
import 'render.dart';

typedef SetupCallback = Render Function();

class SetupWidget extends Widget {
  const SetupWidget({super.key, this.props, required this.setup});

  final Iterable? props;
  final SetupCallback setup;

  @override
  Element createElement() => SetupElement(this);
}

Widget setup(SetupCallback fn) {
  final key = evalKey;
  final props = evalProps;
  final widget = SetupWidget(key: key, props: props, setup: fn);

  evalKey = null;
  evalProps = null;

  return widget;
}
