import 'package:flutter/widgets.dart';

import 'runes/rune.dart';

typedef SetupCallback = Widget Function();

class SetupElement extends ComponentElement {
  static late SetupElement current;

  SetupElement(super.widget, this.callback);

  final SetupCallback callback;

  Rune? runes;
  int cursor = 0;

  late Widget cacheWidget;
  bool mustRebuild = true;

  @override
  Widget build() {
    if (!mustRebuild) return cacheWidget;

    current = this;
    cacheWidget = callback();
    mustRebuild = false;
    cursor = 0;

    return cacheWidget;
  }

  @override
  void update(covariant Widget newWidget) {
    mustRebuild = true;
    super.update(newWidget);
  }

  @override
  void didChangeDependencies() {
    mustRebuild = true;
    super.didChangeDependencies();
  }

  @override
  void reassemble() {
    mustRebuild = true;
    runes?.foreach((rune) => rune.state.reassemble());
    super.reassemble();
  }

  @override
  void unmount() {
    runes?.foreach((rune) => rune.state.unmount());
    super.unmount();
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    runes?.foreach((rune) => rune.state.mount());
  }

  @override
  void activate() {
    super.activate();
    runes?.foreach((rune) => rune.state.activate());
  }

  @override
  void deactivate() {
    runes?.foreach((rune) => rune.state.deactivate());
    super.deactivate();
  }
}

extension<T> on Rune<T> {
  void foreach(void Function(Rune rune) callback) {
    Rune? current = this;
    while (current != null) {
      callback(current);
      current = current.next;
    }
  }
}
