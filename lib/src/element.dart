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
    Rune? rune = runes;
    while (rune != null) {
      rune.state.reassemble();
      rune = rune.next;
    }

    super.reassemble();
  }
}
