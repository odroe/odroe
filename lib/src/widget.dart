import 'package:meta/meta.dart';
import 'package:flutter/widgets.dart';

import 'element.dart';

abstract class OdroeWidget extends Widget {
  const OdroeWidget({super.key});

  @override
  @nonVirtual
  @protected
  OdroeElement createElement() => OdroeElementImpl(this);
}
