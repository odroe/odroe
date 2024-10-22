import 'setup_widget.dart';

SetupElement? _currentElement;
SetupElement? get currentElement => _currentElement;

void Function() setCurrentElement(SetupElement element) {
  final prev = currentElement;
  _currentElement = element;
  element.scope.on();

  return () {
    element.scope.off();
    _currentElement = prev;
  };
}
