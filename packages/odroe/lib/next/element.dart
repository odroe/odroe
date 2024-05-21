import 'package:flutter/widgets.dart';

import 'reactivity/signals.dart';
import 'render.dart';
import 'setup.dart';

SetupElement? evalElement;

class SetupElement extends ComponentElement {
  SetupElement(SetupWidget super.widget);

  @override
  SetupWidget get widget => super.widget as SetupWidget;

  bool shouldSetup = true;
  bool shouldRebuild = true;
  late Widget cachedBuiltWidget;
  late Render render;
  void Function()? cleanup;

  @override
  Widget build() {
    if (!shouldRebuild) return cachedBuiltWidget;

    evalElement = this;
    if (shouldSetup) {
      cleanup?.call();
      render = widget.setup();
      shouldSetup = false;

      cleanup = effect(() {
        cachedBuiltWidget = render();
        shouldRebuild = true;
        markNeedsBuild();
      });
    }

    shouldRebuild = false;

    return cachedBuiltWidget;
  }

  @override
  unmount() {
    super.unmount();
    cleanup?.call();
  }
}
