library;

import 'package:flutter/widgets.dart';

import 'src/element.dart';
import 'src/runes/context.dart';

abstract class SetupWidget extends Widget {
  const SetupWidget({super.key});

  @override
  SetupElement createElement() => SetupElement(this, () => build(context));

  @protected
  Widget build(BuildContext context);
}
