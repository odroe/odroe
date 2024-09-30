class Dependent<T> {
  const Dependent(this.value, this.hasNeedRemove);

  final T value;
  final bool Function(T value) hasNeedRemove;
}
