import '../signal.dart';

bool compareProps<T>(T a, T b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a.runtimeType != b.runtimeType) return false;
  if (a is Iterable && b is Iterable) {
    if (a.length != b.length) return false;

    final aIterator = a.iterator;
    final bIterator = b.iterator;
    while (aIterator.moveNext() && bIterator.moveNext()) {
      if (!compareProps(aIterator.current, bIterator.current)) {
        return false;
      }
    }

    return true;
  }

  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !compareProps(a[key], b[key])) {
        return false;
      }
    }

    return false;
  }

  if (a is Signal || b is Signal) {
    final resolvedA = a is Signal ? a.get() : a;
    final resolvedB = b is Signal ? b.get() : a;

    return compareProps(resolvedA, resolvedB);
  }

  return a == b;
}
