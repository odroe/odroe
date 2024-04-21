import 'package:flutter/widgets.dart';

class RuneState<T, R extends Rune<T>> {
  const RuneState(this.rune);
  final R rune;

  @mustCallSuper
  void activate() {}

  @mustCallSuper
  void deactivate() {}

  @mustCallSuper
  void reassemble() {}

  @mustCallSuper
  void unmount() {}

  @mustCallSuper
  void mount() {}
}

abstract class Rune<T> {
  @protected
  RuneState<T, Rune<T>> createState();

  Rune? next;

  RuneState<T, Rune<T>>? _state;
  RuneState<T, Rune<T>> get state => _state ??= createState();
}
