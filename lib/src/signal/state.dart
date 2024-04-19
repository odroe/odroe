import '../setup.dart';
import 'types.dart';
import 'utils.dart';

class _State<T> implements State<T> {
  _State(this.source, this.element);

  T source;
  final SetupElement element;

  @override
  T get() => source;

  @override
  void set(T value) {
    if (value == source) return;

    source = value;
    element.markNeedsBuild();
  }
}

State<T> state<T>(T source) {
  final rune = findOrCreateRune(
    () => Rune(_State(source, SetupElement.current)),
  );

  return rune.value;
}
