import 'dart:async';

final app = defineModule((module) {
  module.provide(service);
});

final service = defineProvide(
  (ref) => 1,
);

Provide<int> haha() => service;

abstract final class Module {}

abstract class Provide<T> {}

abstract class ModuleRef {
  T call<T>(Provide<T> provide);
}

Module defineModule(void Function(dynamic module) def) {
  throw UnimplementedError();
}

Provide<T> defineProvide<T>(T Function(ModuleRef ref) def) {
  throw UnimplementedError();
}

final class Provider<T> {
  external FutureOr<T> call(ModuleRef ref);

  factory Provider(FutureOr<T> Function(ModuleRef)) = _ProviderImpl;
}

final class _ProviderImpl<T> implements Provider<T> {
  final FutureOr<T> Function(ModuleRef) factory;

  const _ProviderImpl(this.factory);

  @override
  FutureOr<T> call(ModuleRef ref) => factory(ref);
}

final demo = Provider((ref) => 1);
