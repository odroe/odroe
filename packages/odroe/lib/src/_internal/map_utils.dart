import 'iterable_utils.dart';

extension InternalNullableMapUtils<K, V> on Map<K, V>? {
  bool get isNullOrEmpty {
    return switch (this) {
      Map<K, V>(isEmpty: final isEmpty) => isEmpty,
      _ => true,
    };
  }

  bool equals(Map<K, V>? other) {
    return runtimeType == other.runtimeType &&
        this?.itemsHashCode == other?.itemsHashCode;
  }
}

extension InternalMapUtils<K, V> on Map<K, V> {
  Map<K, V> merge(Map<K, V> other) => {...this, ...other};

  Map<K, V> maybeMerge(Map<K, V>? other) {
    if (other == null) return this;

    return merge(other);
  }

  int get itemsHashCode => Object.hashAll([...keys, ...values]);

  Map<K, V> where(bool Function(K key, V value) test) {
    return entries.where((e) => test(e.key, e.value)).toMap();
  }
}
