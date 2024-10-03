/// Check if two objects are different.
///
/// This function is used to check if two objects are different.
bool hasChanged(Object? a, Object? b) {
  return switch ((a, b)) {
    (Map a, Map b) =>
      a.length != b.length || a.keys.any((key) => hasChanged(a[key], b[key])),
    (List a, List b) => _hasIterableChanged(a, b),
    (Set a, Set b) => _hasIterableChanged(a, b),
    (Iterable a, Iterable b) => _hasIterableChanged(a, b),
    _ => a != b,
  };
}

bool _hasIterableChanged(Iterable a, Iterable b) {
  if (a.length != b.length) return true;

  final iteratorA = a.iterator;
  final iteratorB = b.iterator;

  while (iteratorA.moveNext() && iteratorB.moveNext()) {
    if (hasChanged(iteratorA.current, iteratorB.current)) {
      return true;
    }
  }

  return false;
}

class WeakSet<T extends Object> {
  late Expando<bool> _inner = Expando();

  void add(T element) => _inner[element] = true;
  void remove(T element) => _inner[element] = null;
  bool contains(T element) => _inner[element] == true;
  void clear() => _inner = Expando();
}
