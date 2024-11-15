import 'framework.dart';

int currentCallIndex = 0;
final _weekResult = Expando<List>();

T oncecall<T>(T Function() fn) {
  if (currentElement == null) {
    return fn();
  }

  final cache = _weekResult[currentElement!] ??= [];
  if (cache[currentCallIndex] is T) {
    return cache[currentCallIndex];
  } else if (cache.length > currentCallIndex) {
    cache.length = currentCallIndex + 1;
  }

  final result = cache[currentCallIndex] = fn();
  currentCallIndex++;

  return result;
}

Iterable<T> findOncecallResults<T>() {
  if (currentElement != null) {
    final cache = _weekResult[currentElement!];
    if (cache != null && cache.isNotEmpty) {
      return cache.whereType<T>();
    }
  }

  return const [];
}
