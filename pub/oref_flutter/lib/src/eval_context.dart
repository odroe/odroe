import 'package:_octr/_octr.dart';
import 'package:flutter/widgets.dart';

final _ref = findOrCreateEval<BuildContext>();

BuildContext? get evalContext => _ref.value;
set evalContext(BuildContext? value) => _ref.value = value;
