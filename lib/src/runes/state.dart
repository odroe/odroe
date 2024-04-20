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
      element.mustRebuild = true;
      element.markNeedsBuild();
    }
  }

  @override
  StateRuneState<T> get state => super.state as StateRuneState<T>;

  @override
  RuneState<T> createState() => StateRuneState(this);
}

class StateRuneState<T> extends RuneState<T> {
  const StateRuneState(super.rune);

  @override
  StateRune<T> get rune => super.rune as StateRune<T>;

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