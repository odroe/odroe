import '../../types/private.dart' as private;
import '../batch.dart' as impl;
import '../ref.dart' as impl;

final class ReactiveMap<K, V> extends impl.BaseRef<Map<K, V>>
    implements private.Reactive<Map<K, V>>, Map<K, V> {
  ReactiveMap(super.raw);

  @override
  V? operator [](Object? key) => value[key];

  @override
  void operator []=(K key, V value) {
    final prev = raw[key];
    this.value[key] = value;

    if (!identical(prev, value)) {
      dep.trigger();
    }
  }

  @override
  void addAll(Map<K, V> other) {
    raw.addAll(other);
    dep.trigger();
  }

  @override
  void addEntries(Iterable<MapEntry<K, V>> newEntries) {
    raw.addEntries(newEntries);
    dep.trigger();
  }

  @override
  Map<RK, RV> cast<RK, RV>() => Map.castFrom(this);

  @override
  void clear() {
    raw.clear();
    dep.trigger();
  }

  @override
  bool containsKey(Object? key) => value.containsKey(key);

  @override
  bool containsValue(Object? value) {
    return this.value.containsValue(value);
  }

  @override
  Iterable<MapEntry<K, V>> get entries {
    return value.entries;
  }

  @override
  @Deprecated('Try using for loop.')
  void forEach(void Function(K key, V value) action) {
    dep.track();
    impl.startBatch();
    for (final MapEntry(:key, :value) in entries) {
      action(key, value);
    }
    impl.endBatch();
  }

  @override
  bool get isEmpty => value.isEmpty;

  @override
  bool get isNotEmpty => value.isNotEmpty;

  @override
  Iterable<K> get keys => value.keys;

  @override
  int get length => value.length;

  @override
  Map<K2, V2> map<K2, V2>(MapEntry<K2, V2> Function(K key, V value) convert) {
    return value.map(convert);
  }

  @override
  V putIfAbsent(K key, V Function() ifAbsent) {
    bool markNeedTrigger = false;
    try {
      return value.putIfAbsent(key, () {
        markNeedTrigger = true;
        return ifAbsent();
      });
    } finally {
      if (markNeedTrigger) dep.trigger();
    }
  }

  @override
  V? remove(Object? key) {
    final removed = raw.remove(key);
    if (removed != null) dep.trigger();

    return removed;
  }

  @override
  void removeWhere(bool Function(K key, V value) test) {
    bool makeNeedTrigger = false;
    raw.removeWhere((key, value) {
      if (test(key, value)) {
        return makeNeedTrigger = true;
      }

      return false;
    });

    if (makeNeedTrigger) dep.trigger();
  }

  @override
  V update(K key, V Function(V value) update, {V Function()? ifAbsent}) {
    final prev = raw[key];
    final value = raw.update(key, update, ifAbsent: ifAbsent);

    if (!identical(prev, value)) {
      dep.trigger();
    }

    return value;
  }

  @override
  void updateAll(V Function(K key, V value) update) {
    bool needTrigger = false;
    raw.updateAll((key, oldValue) {
      final newValue = update(key, oldValue);
      if (!needTrigger && !identical(oldValue, newValue)) {
        needTrigger = true;
      }

      return newValue;
    });

    if (needTrigger) dep.trigger();
  }

  @override
  Iterable<V> get values => value.values;
}
