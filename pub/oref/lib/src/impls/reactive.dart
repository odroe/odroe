import '../types/private.dart' as private;

bool isReactive<T>(T value) => value is private.Reactive;

T toRaw<T>(T value) {
  if (value is private.Reactive) {
    return toRaw(value.raw);
  }

  return value;
}
