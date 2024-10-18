import '../types/public.dart' as public;
import '../types/private.dart' as private;
import 'collections/reactive_list.dart' as impl;
import 'collections/reactive_map.dart' as impl;

bool isCollection<T>(T value) {
  return value is Map || value is List || value is Set;
}

bool isReactive<T>(T value) => value is private.Reactive;

T createReactive<T>(T raw, private.Dep dep, bool shallow) {
  if (isReactive(raw)) return raw;

  return switch (toRaw(raw)) {
    Map map => impl.ReactiveMap(map, dep, shallow) as T,
    List list => impl.ReactiveList(list, dep, shallow) as T,
    Set set => impl.ReactiveSet(set, dep, shallow) as T,
    _ => throw UnsupportedError('Reactive only support collections'),
  };
}

T toRaw<T>(T value) {
  if (value is private.Reactive) {
    return toRaw(value.raw);
  } else if (value is Iterable && value.any((e) => isReactive(e))) {
    final raw = value.map((e) => toRaw(e));
    return switch (value) {
      List() => raw.toList() as T,
      Set() => raw.toSet() as T,
      _ => raw as T,
    };
  } else if (value is Map && value.values.any((e) => isReactive(e))) {
    return value.map((key, value) => MapEntry(key, toRaw(value))) as T;
  }

  return value;
}
