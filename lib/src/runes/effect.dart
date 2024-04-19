import 'package:flutter/widgets.dart';
import 'package:odroe/src/runes/rune.dart';

import 'utils.dart';

typedef EffectCallback = VoidCallback? Function();

class EffectRune extends Rune<void> {
  EffectRune(this.callback, this.deps);

  final EffectCallback callback;
  VoidCallback? cleanup;
  Iterable deps;

  @override
  RuneState<void> createState() => EffectRuneState(this);
}

class EffectRuneState extends RuneState<void> {
  EffectRuneState(super.rune);

  @override
  EffectRune get rune => super.rune as EffectRune;

  @override
  void reassemble() {
    super.reassemble();

    rune.cleanup?.call();
    rune.cleanup = rune.callback();
  }

  @override
  void unmount() {
    super.unmount();

    rune.cleanup?.call();
    rune.cleanup = null;
  }

  @override
  void mount() {
    super.mount();

    assert(rune.cleanup == null);
    rune.cleanup = rune.callback();
  }
}

void effect(EffectCallback fn, [Iterable deps = const []]) {
  final computedDeps = createDeps(deps);
  final rune = findOrCreateRune(() => EffectRune(fn, computedDeps));

  if (!compareDeps(rune.deps, computedDeps) && deps.isNotEmpty) {
    rune.cleanup?.call();
    rune.cleanup = rune.callback();
  }
}
