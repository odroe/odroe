import 'package:flutter/widgets.dart';

import 'types.dart';

Element? evalElement;

void autoScope<T>(Element element, T value) {
  if (value is Ref) {
    evalElement = element;
  }
}
