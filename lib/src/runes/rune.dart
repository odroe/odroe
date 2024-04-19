import 'package:flutter/widgets.dart';

class RuneState<T> {
  const RuneState(this.rune);
  final Rune<T> rune;

  @mustCallSuper
  void reassemble() {}
}

abstract class Rune<T> {
  @protected
  RuneState<T> createState() => RuneState(this);

  Rune? next;

  RuneState<T>? _state;
  RuneState<T> get state => _state ??= createState();
}
