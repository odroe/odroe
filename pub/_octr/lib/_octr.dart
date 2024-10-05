final _typed = <WeakReference<Expando>>[];
final _marked = Expando<Expando>();

/// Creates a container.
Expando<T> createWeakMap<T extends Object>([Object? mark]) {
  if (mark == null) {
    for (final WeakReference(:target) in _typed) {
      if (target is Expando<T>) {
        return target;
      }
    }

    final expando = Expando<T>();
    _typed.add(WeakReference(expando));

    return expando;
  }

  final expando = _marked[mark] ??= Expando<T>();
  if (expando is Expando<T>) {
    return expando;
  }

  throw StateError('Invalid mark, the mark is already used for another type.');
}
