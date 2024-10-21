import '../impls/reactive.dart' as impl;
import '../impls/collections/reactive_map.dart' as impl;
import '../impls/collections/reactive_set.dart' as impl;
import '../impls/collections/reactive_list.dart' as impl;
import '../impls/collections/reactive_iterable.dart' as impl;

export '../impls/reactive.dart' show toRaw, isReactive;

/// Creates a reactive map from the given [map].
///
/// If [map] is already reactive, it is returned as-is.
/// Otherwise, a new reactive [Map] is created from the raw value.
///
/// [K] is the type of the map keys.
/// [V] is the type of the map values.
Map<K, V> reactiveMap<K, V>(Map<K, V> map) {
  if (impl.isReactive(map)) {
    return map;
  }

  return impl.ReactiveMap<K, V>(impl.toRaw(map));
}

/// Creates a reactive set from the given [set].
///
/// If [set] is already reactive, it is returned as-is.
/// Otherwise, a new reactive [Set] is created from the raw value.
///
/// [E] is the type of elements in the set.
Set<E> reactiveSet<E>(Set<E> set) {
  if (impl.isReactive(set)) {
    return set;
  }

  return impl.ReactiveSet<E>(impl.toRaw(set));
}

/// Creates a reactive list from the given [list].
///
/// If [list] is already reactive, it is returned as-is.
/// Otherwise, a new reactive [List] is created from the raw value.
///
/// [E] is the type of elements in the list.
List<E> reactiveList<E>(List<E> list) {
  if (impl.isReactive(list)) {
    return list;
  }

  return impl.ReactiveList<E>(impl.toRaw(list));
}

/// Creates a reactive iterable from the given [iterable].
///
/// If [iterable] is already reactive, it is returned as-is.
/// Otherwise, a new reactive [Iterable] is created from the raw value.
///
/// [E] is the type of elements in the iterable.
Iterable<E> reactiveIterable<E>(Iterable<E> iterable) {
  if (impl.isReactive(iterable)) {
    return iterable;
  }

  return impl.ReactiveIterable<E>(impl.toRaw(iterable));
}
