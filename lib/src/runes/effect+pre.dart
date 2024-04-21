// ignore_for_file: file_names

import 'package:flutter/widgets.dart';

import 'effect.dart';
import 'rune.dart';
import 'utils.dart';

class EffectPreRune extends Rune<void> {
  EffectPreRune(this.callback);

  final EffectCallback callback;
  VoidCallback? cleanup;

  @override
  RuneState<void, Rune<void>> createState() => EffectPreRuneState(this);
}

class EffectPreRuneState extends RuneState<void, EffectPreRune> {
  EffectPreRuneState(super.rune);
}

/// [pre] extension on [$effect].
extension Effect$Pre on Effect {
  /// In rare cases, you need to run code before Widgets. For this we can use
  /// the `$effect.pre` rune.
  ///
  /// Allows you to return a cleanup function in [fn], whenever Setup-widget is
  /// updated, you can clean up some dirty data.
  void pre(EffectCallback fn) {
    final rune = findOrCreateRune(() => EffectPreRune(fn));

    rune.cleanup?.call();
    rune.cleanup = rune.callback();
  }
}
