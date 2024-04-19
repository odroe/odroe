import 'package:flutter/widgets.dart';

import 'element.dart';

class SetupWidget extends Widget {
  const SetupWidget(this.fn, {super.key});

  final SetupCallback fn;

  @override
  SetupElement createElement() => SetupElement(this, fn);
}

Widget setup(SetupCallback fn, {Key? key}) => SetupWidget(fn, key: key);
