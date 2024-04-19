import 'package:flutter/widgets.dart';

class RuneState<T> {
  const RuneState(this.rune);
  final Rune<T> rune;

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
  RuneState<T> createState() => RuneState(this);

  Rune? next;

  RuneState<T>? _state;
  RuneState<T> get state => _state ??= createState();
}
