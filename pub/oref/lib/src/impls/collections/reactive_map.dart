import '../../types/private.dart' as private;
import '../reactive.dart' as impl;

class ReactiveMap<K, V> implements private.Reactive<Map<K, V>>, Map<K, V> {
  ReactiveMap(this.raw, this.dep, this.shallow);

  late final Map<K, V> targets = {};

  @override
  Map<K, V> raw;

  @override
  final bool shallow;

  @override
  final private.Dep dep;

  @override
  Map<K, V> get value {
    dep.track();
    return this;
  }

  @override
  set value(Map<K, V> newValue) {
    raw = impl.toRaw(newValue);
    dep.trigger();
  }

  @override
  V? operator [](Object? key) {
    dep.track();

    final value = raw[key];
    if (key is K && !shallow && impl.isCollection(value)) {
      return targets[key] ??= impl.createReactive(value as V, dep, shallow);
    }

    return value;
  }

  @override
  void operator []=(K key, V value) {
    final oldValue = raw[key];
    final newValue = impl.toRaw(value);

    if (identical(oldValue, newValue)) {
      return;
    }

    raw[key] = newValue;
    if (!shallow) {
      targets.remove(key);
    }

    dep.trigger();
  }

  @override
  void addAll(Map<K, V> other) {
    final rawOther = impl.toRaw(other);
    raw.addAll(rawOther);
    for (final key in other.keys) {
      targets.remove(key);
    }

    dep.trigger();
  }

  @override
  void addEntries(Iterable<MapEntry<K, V>> newEntries) {
    raw.addEntries(newEntries.map((e) => MapEntry(e.key, impl.toRaw(e.value))));
    for (final key in newEntries.map((e) => e.key)) {
      targets.remove(key);
    }

    dep.trigger();
  }

  @override
  Map<RK, RV> cast<RK, RV>() => Map.castFrom(this);

  @override
  void clear() {
    raw.clear();
    targets.clear();
    dep.trigger();
  }

  @override
  bool containsKey(Object? key) {
    dep.track();

    return raw.containsKey(key);
  }

  @override
  bool containsValue(Object? value) {
    dep.track();

    return raw.containsValue(value);
  }

  @override
  Iterable<MapEntry<K, V>> get entries sync* {
    dep.track();

    if (shallow) {
      yield* raw.entries;
      return;
    }

    for (final MapEntry(:key, :value) in raw.entries) {
      if (impl.isCollection(value)) {
        yield MapEntry(
          key,
          targets[key] ??= impl.createReactive(value, dep, shallow),
        );
        continue;
      }

      yield MapEntry(key, value);
    }
  }

  @override
  @Deprecated('Try using for loop.')
  void forEach(void Function(K key, V value) action) {
    for (final MapEntry(:key, :value) in entries) {
      action(key, value);
    }
  }

  @override
  bool get isEmpty {
    dep.track();
    return raw.isEmpty;
  }

  @override
  bool get isNotEmpty {
    dep.track();
    return raw.isNotEmpty;
  }

  @override
  Iterable<K> get keys {
    dep.track();

    return raw.keys;
  }

  @override
  int get length {
    dep.track();

    return raw.length;
  }

  @override
  Map<K2, V2> map<K2, V2>(MapEntry<K2, V2> Function(K key, V value) convert) {
    dep.track();
    return raw.map(convert);
  }

  @override
  V putIfAbsent(K key, V Function() ifAbsent) {
    dep.track();

    bool markNeedTrigger = false;
    try {
      final value = raw.putIfAbsent(key, () {
        markNeedTrigger = true;
        return ifAbsent();
      });

      if (shallow || !impl.isCollection(value)) {
        return value;
      }

      return targets[key] ??= impl.createReactive(value, dep, shallow);
    } finally {
      if (markNeedTrigger) dep.trigger();
    }
  }

  @override
  V? remove(Object? key) {
    final oldValue = raw[key];
    final removedValue = raw.remove(key);

    targets.remove(key);
    if (!identical(oldValue, removedValue)) {
      dep.trigger();
    }

    return impl.toRaw(removedValue);
  }

  @override
  void removeWhere(bool Function(K key, V value) test) {
    final keys = <K>[];
    bool makeNeedTrigger = false;
    raw.removeWhere((key, value) {
      final result = test(key, impl.toRaw(value));
      if (result) {
        makeNeedTrigger = true;
        keys.add(key);
      }

      return result;
    });

    for (final key in keys) {
      targets.remove(key);
    }

    if (makeNeedTrigger) {
      dep.trigger();
    }
  }

  @override
  V update(K key, V Function(V value) update, {V Function()? ifAbsent}) {
    final oldValue = raw[key];
    final newValue = raw.update(
      key,
      (value) => update(impl.toRaw(value)),
      ifAbsent: switch (ifAbsent) {
        null => null,
        _ => () => impl.toRaw(ifAbsent()),
      },
    );

    if (!identical(oldValue, value)) {
      dep.trigger();
    }

    targets.remove(key);
    if (shallow || !impl.isCollection(value)) {
      return newValue;
    }

    return targets[key] = impl.createReactive(newValue, dep, shallow);
  }

  @override
  void updateAll(V Function(K key, V value) update) {
    final keys = <K>[];
    bool needTrigger = false;
    raw.updateAll((key, oldValue) {
      final newValue = impl.toRaw(update(key, impl.toRaw(oldValue)));
      if (!needTrigger && !identical(oldValue, newValue)) {
        needTrigger = true;
        keys.add(key);
      }

      return newValue;
    });

    for (final key in keys) {
      targets.remove(key);
    }

    if (needTrigger) {
      dep.trigger();
    }
  }

  @override
  Iterable<V> get values sync* {
    dep.track();
    if (shallow) {
      yield* raw.values;
      return;
    }

    for (final MapEntry(:key, :value) in raw.entries) {
      if (impl.isCollection(value)) {
        yield targets[key] ??= impl.createReactive(value, dep, shallow);
        continue;
      }

      yield value;
    }
  }
}
