void Function() effect<T>(
  T Function() _, {
  void Function(T)? onCleanup,
}) {
  throw UnimplementedError();
}

T untracked<T>(T Function() _) {
  throw UnimplementedError();
}

void batch(void Function() _) {
  throw UnimplementedError();
}
