import '../element.dart';
import '../signal.dart';
import 'rune.dart';
import 'utils.dart';

class StateRune<T> extends Rune<T> implements State<T> {
  StateRune(this.initalValue, this.element) : source = initalValue;

  final T initalValue;
  final SetupElement element;

  late T source;

  @override
  T get() => source;

  @override
  void set(T value) {
    if (source == value) return;

    source = value;
    element.mustRebuild = true;
    element.markNeedsBuild();
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

State<T> state<T>(T source) {
  final element = SetupElement.current;
  final rune = findOrCreateRune(
    () => StateRune(source, element),
  );

  return rune;
}
