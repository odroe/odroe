import 'package:odroe/src/setup.dart';

abstract interface class Signal<T> {
  T get();
}

abstract interface class State<T> implements Signal<T> {
  void set(T value);
}

abstract interface class Computed<T> implements Signal<T> {}

class _State<T> implements State<T> {
  _State(this.source, this.element);

  T source;
  final SetupElement element;

  @override
  T get() => source;

  @override
  void set(T value) {
    if (value == source) return;

    source = value;
    element.markNeedsBuild();
  }
}

State<T> state<T>(T source) {
  final element = SetupElement.current;

  if (element.runes == null) {
    final state = _State(source, element);
    element.runes = Rune(state);

    element.cursor++;

    return state;
  }

  // 查找游标的 Rune
  int cursor = 0;
  Rune rune = element.runes!;
  while (cursor != element.cursor) {
    if (rune.next == null) {
      final state = _State(source, element);
      rune.next = Rune(state);

      if ((cursor + 1) != element.cursor) {
        throw Error();
      }
      break;
    }

    rune = rune.next!;
    cursor++;
  }

  element.cursor++;
  if (rune.value is _State) {
    return rune.value;
  }

  final state = _State(source, element);
  rune.next = Rune(state);

  return state;
}
