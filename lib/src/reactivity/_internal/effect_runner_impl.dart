import '../types.dart';

final class EffectRunnerImpl<T> implements EffectRunner<T> {
  const EffectRunnerImpl(this.effect);

  @override
  final Effect<T> effect;

  @override
  T call() => effect.run();
}
