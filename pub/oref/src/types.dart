// abstract interface class Readonly<T, R extends Ref<T>> implements Ref<T> {}

// abstract interface class Computed<T> implements Readonly<T, Ref<T>> {}

// // WritableRef<T> ref<T>(T _) => throw UnimplementedError();

// // Readonly<T, R> readonly<T, R extends Ref<T>>(R _) => throw UnimplementedError();

// Computed<T> computed<T>(T Function() _) => throw UnimplementedError();

// abstract interface class Effect<T> {}

// abstract interface class EffectRunner<T> {
//   T call();
//   Effect get effect;
// }

// EffectRunner<T> effect<T>(T Function() _) => throw UnimplementedError();
// void batch(void Function() _) => throw UnimplementedError();
// R watch<T, R>(T Function() _, R Function(T _, T? __) __) =>
//     throw UnimplementedError();
