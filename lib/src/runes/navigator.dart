import 'package:flutter/widgets.dart';
import 'package:odroe/src/runes/context.dart';

NavigatorState $navigator({bool root = false}) =>
    Navigator.of($context(), rootNavigator: root);
