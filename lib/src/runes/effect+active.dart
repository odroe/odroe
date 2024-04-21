// ignore_for_file: file_names

import 'package:flutter/widgets.dart';
import 'package:odroe/src/runes/rune.dart';

import 'effect.dart';
import 'utils.dart';

class EffectActiveRune extends Rune<void> {
  EffectActiveRune(this.callback);

  final EffectCallback callback;
  VoidCallback? cleanup;

  @override
  RuneState<void, EffectActiveRune> createState() =>
      EffectActiveRuneState(this);
}

class EffectActiveRuneState extends RuneState<void, EffectActiveRune> {
  const EffectActiveRuneState(super.rune);

  @override
  void activate() {
    assert(rune.cleanup == null);
    super.activate();
    rune.cleanup = rune.callback();
  }

  @override
  void deactivate() {
    rune.cleanup?.call();
    rune.cleanup = null;

    super.deactivate();
  }

  @override
  void reassemble() {
    super.reassemble();

    rune.cleanup?.call();
    rune.cleanup = null;
    rune.cleanup = rune.callback();
  }
}

/// [active] extension on [$effect].
extension Effect$Active on Effect {
  /// Active effect, affects whether Setup-widget is active in the current
  /// screen.
  ///
  /// [callback] If a function with a [VoidCallback] signature is returned, it
  /// will be called when the Setup-widget is no longer active.
  void active(EffectCallback fn) {
    findOrCreateRune(() => EffectActiveRune(fn));
  }
}
