// ignore: implementation_imports
import 'package:oref/src/impls/global.dart' as oref;

import 'setup_widget.dart';

SetupElementImpl? _currentElement;
SetupElementImpl? get currentElement => _currentElement;

void Function() setCurrentElement(SetupElementImpl element) {
  final prevElement = currentElement;
  final prevSub = oref.activeSub;

  _currentElement = element;
  oref.activeSub = element.effect;
  element.scope.on();

  return () {
    element.scope.off();
    oref.activeSub = prevSub;
    _currentElement = prevElement;
  };
}
