// import '../setup.dart';
// import '../signal.dart';
// import 'rune.dart';
// import 'utils.dart';

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
  ComputedRuneState<T> get state => super.state as ComputedRuneState<T>;

  @override
  T get() => source;

  @override
  RuneState<T> createState() => ComputedRuneState(this);
}

class ComputedRuneState<T> extends RuneState<T> {
  const ComputedRuneState(super.rune);

  @override
  ComputedRune<T> get rune => super.rune as ComputedRune<T>;

  void rebuild() {
    rune.source = rune.callback();
  }
}

Computed<T> computed<T>(ComputedCallback<T> fn, [Iterable deps = const []]) {
  final element = SetupElement.current;
  final computedDeps = createDeps(deps);
  final rune = findOrCreateRune(() {
    final computed = ComputedRune<T>(fn, element, computedDeps);
    computed.state.rebuild();

    return computed;
  });

  if (!compareDeps(rune.deps, computedDeps)) {
    rune.state.rebuild();
    rune.element.mustRebuild = true;
  }

  return rune;
}
