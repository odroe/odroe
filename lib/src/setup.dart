import 'package:flutter/widgets.dart';

typedef SetupCallback = Widget Function();

Widget setup(SetupCallback fn, {Key? key}) => SetupWidget(fn, key: key);

class Rune<T> {
  Rune(this.value);

  final T value;
  Rune? next;
}

class SetupWidget extends Widget {
  const SetupWidget(this.fn, {super.key});

  final SetupCallback fn;

  @override
  Element createElement() => SetupElement(this);
}

class SetupElement extends ComponentElement {
  static late SetupElement current;

  SetupElement(super.widget) {
    current = this;
  }

  Rune? runes;
  int cursor = 0;

  @override
  Widget build() {
    current = this;
    final result = (widget as SetupWidget).fn();
    cursor = 0;

    return result;
  }
}
