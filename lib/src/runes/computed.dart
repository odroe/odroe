import '../element.dart';
import '../signal.dart';
import 'rune.dart';
import 'utils.dart';

typedef ComputedCallback<T> = T Function();

class ComputedRune<T> extends Rune<T> implements Computed<T> {
  ComputedRune(this.callback, this.element, this.deps);

  final ComputedCallback<T> callback;
  final SetupElement element;

  late T source;
  Iterable deps;

  @override
  T get() => source;

  void rebuild() => source = callback();
}

Computed<T> computed<T>(ComputedCallback<T> fn, [Iterable deps = const []]) {
  final element = SetupElement.current;
  final computedDeps = createDeps(deps);
  final rune = findOrCreateRune(() {
    final computed = ComputedRune<T>(fn, element, computedDeps);
    computed.rebuild();

    return computed;
  });

  if (!compareDeps(rune.deps, computedDeps)) {
    rune.rebuild();
    rune.element.mustRebuild = true;
  }

  return rune;
}
