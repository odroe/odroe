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
  RuneState<void, Rune<void>> createState() => EffectRuneState(this);
}

class EffectRuneState extends RuneState<void, EffectRune> {
  EffectRuneState(super.rune);

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

/// Creates a effect rune for the [SetupWidget].
///
/// ## `mount/unmount` effect
///
/// This is the most basic usage, which only has one side effect in
/// [SetupWidget].
///
/// ```dart
/// Widget example() => setup(() {
///   $effect(() {
///     print('Mount');
///     return () => print('Unmount');
///   });
///
///   ...
/// });
/// ```
///
/// ## Value effect
///
/// You can also pass the second parameter [$effect] so that its side effects
/// are not just limited to the 'mount/unmount' lifecycle. However, [deps]
/// updates will have side effects.
///
/// ```dart
/// Widget example() => setup(() {
///   final value = $state(0);
///
///   $effect(() {
///     print('Effect value: ${value.get()}');
///   }, [value]); // Dep value, value change rerun effect.
/// });
/// ```
///
/// ## Props
///
/// - [fn]: Effect callback, Optionally, return a cleanup function. If cleanup
/// is returned, it will run when the 'unmount' event occurs.
/// - [deps]: Optional, representing the list of changes that the effect wants
/// to rely on. When the value changes, the effect will be rerun.
void $effect(EffectCallback fn, [Iterable deps = const []]) {
  final computedDeps = createDeps(deps);
  final rune = findOrCreateRune(() => EffectRune(fn, computedDeps));

  if (!compareDeps(rune.deps, computedDeps) && deps.isNotEmpty) {
    rune.cleanup?.call();
    rune.cleanup = rune.callback();
  }
}

/// The [$effect] type.
typedef Effect = void Function(EffectCallback fn, [Iterable deps]);
