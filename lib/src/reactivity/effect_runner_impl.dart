import 'types.dart';

final class EffectRunnerImpl<T> implements EffectRunner<T> {
  EffectRunnerImpl(this.value, this.effect);

  @override
  final Effect<T> effect;

  @override
  T call() => value = effect.run();

  @override
  T value;
}
