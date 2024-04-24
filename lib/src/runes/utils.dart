import 'package:odroe/odroe.dart';

import '../element.dart';
import '../signal.dart';
import 'rune.dart';

typedef RuneCreator<T, R extends Rune<T>> = R Function();

R findOrCreateRune<T, R extends Rune<T>>(RuneCreator<T, R> creator) {
  final element = SetupElement.current;
  assert(element.mounted);

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

  if (rune is R) {
    element.cursor++;
    return rune;
  }

  final result = rune.next = creator();
  element.cursor++;

  return result;
}

bool compareDeps(Iterable a, Iterable b) {
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

    return switch (element) {
      Signal(get: final get) => get(),
      Iterable sources => createDeps(sources),
      _ => element,
    };
  }, growable: false);
}
