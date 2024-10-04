Expando<E> _createExpando<T, E extends Object>() => Expando<E>('oref: $T');

final class WeakSet<E extends Object> {
  late Expando<bool> _expando = _createExpando<WeakSet<E>, bool>();

  void add(E value) => _expando[value] = true;
  void remove(E value) => _expando[value] = null;
  void clear() => _expando = _createExpando<WeakSet<E>, bool>();
  bool contains(E value) => _expando[value] == true;
}

final class WeakMap<K extends Object, V extends Object> {
  late Expando<V> _expando = _createExpando<WeakMap<K, V>, V>();

  void operator []=(K key, V value) => _expando[key] = value;
  V? operator [](K key) => _expando[key];
  void remove(K key) => _expando[key] = null;
  void clear() => _expando = _createExpando<WeakMap<K, V>, V>();
  bool containsKey(K key) => _expando[key] != null;
}
