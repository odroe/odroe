import '../types.dart';

ReadonlyRef<T, S> readonly<T, S extends Ref<T>>(S ref) => _ReadonlyRefImpl(ref);

class _ReadonlyRefImpl<T, S extends Ref<T>> implements ReadonlyRef<T, S> {
  const _ReadonlyRefImpl(this.ref);

  final S ref;

  @override
  T get value => ref.value;
}
