import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'oncecall.dart';
import 'reactivity/effect_impl.dart';
import 'reactivity/effect_scope_impl.dart';
import 'reactivity/subscriber.dart';
import 'reactivity/types.dart';
import 'render.dart';
import 'scheduler.dart';

abstract class OdroeWidget extends Widget {
  const OdroeWidget({super.key});

  @protected
  WidgetRender setup();

  @override
  @nonVirtual
  @protected
  OdroeElement createElement() => OdroeElementImpl(this);
}

abstract final class OdroeElement implements Element {}

OdroeElementImpl? currentElement;
int _evalElementId = 0;

final class OdroeElementImpl extends ComponentElement implements OdroeElement {
  OdroeElementImpl(OdroeWidget super.widget) : id = _evalElementId++ {
    final prevElement = currentElement;
    final prevCallIndex = currentCallIndex;
    final resetActiveSub = setActiveSub(effect);

    currentElement = this;
    scope.on();

    try {
      render = widget.setup();
    } finally {
      resetActiveSub();
      scope.off();
      currentElement = prevElement;
      currentCallIndex = prevCallIndex;
    }
  }

  late final EffectScope scope = effectScope(true);
  late final EffectImpl effect = () {
    scope.on();
    try {
      // return EffectImpl(() => queueJob(job));
      return EffectImpl(() {});
    } finally {
      scope.off();
    }
  }();

  final int id;
  late final job = SchedulerJob(id, () {
    // print(111);
    if (effect.dirty || dirty) markNeedsBuild();
  });

  late WidgetRender render;
  late Widget built;

  @override
  OdroeWidget get widget {
    assert(super.widget is OdroeWidget);
    return super.widget as OdroeWidget;
  }

  @override
  Widget build() {
    // final reset = setActiveSub(effect);
    try {
      return render();
    } finally {
      // reset();
    }
  }
}
