import 'framework.dart';

int currentCallIndex = 0;
final _weekResult = Expando<List>();

T oncecall<T>(T Function() fn) {
  if (currentElement == null) {
    return fn();
  }

  final cache = _weekResult[currentElement!] ??= [];
  T? result = cache.elementAtOrNull(currentCallIndex);

  if (result is T) {
    return result;
  } else if (cache.length > currentCallIndex) {
    cache.length = currentCallIndex + 1;
  }

  result = fn();
  cache.insert(currentCallIndex, result);

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
