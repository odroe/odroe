import '../setup.dart';
import 'types.dart';

typedef RuneCreator<T> = Rune<T> Function();

Rune<T> findOrCreateRune<T>(RuneCreator<T> creator) {
  final element = SetupElement.current;
  if (element.runes == null) {
    final rune = creator();
    element.runes = rune;
    element.cursor++;

    return rune;
  }

  int cursor = 0;
  Rune rune = element.runes!;
  while (cursor != element.cursor) {
    if (rune.next == null) {
      rune.next = creator();

      assert((cursor + 1) == element.cursor);
    }

    rune = rune.next!;
    cursor++;
  }

  if (rune is Rune<T>) {
    element.cursor++;
    return rune;
  }

  final result = rune.next = creator();
  element.cursor++;

  return result;
}

bool compareIterable(Iterable a, Iterable b) {
  if (a.length != b.length) return false;

  final aIterator = a.iterator;
  final bIterator = b.iterator;
  while (aIterator.moveNext() && bIterator.moveNext()) {
    final aValue = aIterator.current;
    final bValue = bIterator.current;

    if (aValue != bValue) return false;
  }

  return true;
}

Iterable createDeps(Iterable sources) {
  return List.generate(sources.length, (index) {
    final element = sources.elementAt(index);
    if (element is Signal) {
      return element.get();
    }

    return element;
  }, growable: false);
}
