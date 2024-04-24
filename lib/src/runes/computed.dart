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

  @override
  RuneState<T, Rune<T>> createState() => ComputedRuneState(this);
}

class ComputedRuneState<T> extends RuneState<T, ComputedRune<T>> {
  const ComputedRuneState(super.rune);
}

/// Create a computed Signal.
///
/// [$computed] Used to create a computed signal based on callback calculation
/// values:
///
/// ```dart
/// Widget calculation() => setup(() {
///   final numbers = $state(<int>[]);
///   final total = $computed(() {
///     int result = 0;
///     for (final n in numbers.get()) {
///       result += n;
///     }
///
///     return result;
///   }, [numbers]);
/// });
/// ```
///
/// - [deps]: By default, as long as the signal is updated, it will run again.
/// But if you want to recalculate and return a new value only when a certain
/// data is updated, you will need to pay attention to it. For example, your
/// Setup Widget has multiple Reactive data, and only updates the value when
/// one of the values changes. If deps is not passed, any update will trigger a
/// recalculation, resulting in meaningless logical execution.
Computed<T> $computed<T>(ComputedCallback<T> fn, [Iterable deps = const []]) {
  final element = SetupElement.current;
  final computedDeps = createDeps(deps);
  final rune = findOrCreateRune(() {
    final computed = ComputedRune<T>(fn, element, computedDeps);
    computed.rebuild();

    return computed;
  });

  if (!compareDeps(rune.deps, computedDeps)) {
    rune.rebuild();
    rune.element.shouldRebuild = true;
  }

  return rune;
}
