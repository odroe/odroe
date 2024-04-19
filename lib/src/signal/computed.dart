import 'package:odroe/odroe.dart';

import '../setup.dart';
import 'types.dart';
import 'utils.dart';

typedef ComputedCallback<T> = T Function();

class _Computed<T> implements Computed<T> {
  _Computed(this.fn, this.element, this.deps);

  final ComputedCallback fn;
  final SetupElement element;

  final Iterable deps;
  late T source;

  @override
  T get() => source;

  void update() => source = fn();
}

Computed<T> computed<T>(ComputedCallback<T> fn, [Iterable deps = const []]) {
  final computedDeps = createDeps(deps);
  final rune = findOrCreateRune(() {
    final computed = _Computed<T>(fn, SetupElement.current, computedDeps);
    computed.update();

    return Rune(computed);
  });

  if (compareIterable(rune.value.deps, computedDeps)) {
    return rune.value;
  }

  return rune.value..update();
}
