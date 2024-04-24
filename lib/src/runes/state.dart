import '../element.dart';
import '../signal.dart';
import 'rune.dart';
import 'utils.dart';

class StateRune<T> extends Rune<T> implements State<T> {
  StateRune(this.initalValue, this.element, {required this.wantRebuild})
      : source = initalValue;

  final T initalValue;
  final SetupElement element;
  final bool wantRebuild;

  late T source;

  @override
  T get() => source;

  @override
  void set(T value) {
    if (source == value) return;

    source = value;
    if (wantRebuild) {
      element.shouldRebuild = true;
      element.markNeedsBuild();
    }
  }

  @override
  void update(T Function(T value) updater) => set(updater(source));

  @override
  RuneState<T, Rune<T>> createState() => StateRuneState(this);
}

class StateRuneState<T> extends RuneState<T, StateRune<T>> {
  const StateRuneState(super.rune);

  @override
  void reassemble() {
    rune.source = rune.initalValue;
    super.reassemble();
  }
}

/// Create a reactive state for [SetupWidget].
///
/// [$state] is used to create a responsive state in [SetupWidget], which
/// returns a read-write Signal:
///
/// ```dart
/// Widget counter() => setup(() {
///   final count = $state(0);
///
///   return Text('Count: ${count.get()}');
/// });
/// ```
State<T> $state<T>(T source, {bool wantRebuild = true}) {
  final element = SetupElement.current;
  final rune = findOrCreateRune(
    () => StateRune(source, element, wantRebuild: wantRebuild),
  );

  return rune;
}
