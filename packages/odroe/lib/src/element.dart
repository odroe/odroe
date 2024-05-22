import 'package:flutter/widgets.dart';

import 'hooks/lifecycle_hooks.dart';
import 'reactivity/signals.dart';
import 'render.dart';
import 'setup.dart';

SetupElement? evalElement;

SetupElement getCurrentElement() {
  assert(evalElement != null);
  return evalElement!;
}

class SetupElement extends ComponentElement {
  SetupElement(SetupWidget super.widget);

  @override
  SetupWidget get widget => super.widget as SetupWidget;

  bool _initializedSetup = false;
  late Widget cachedBuiltWidget;
  late Render render;
  late final List<Signal> props;
  void Function()? cleanup;
  final lifecycle = <Lifecycle>[];

  @override
  Widget build() {
    evalElement = this;
    if (!_initializedSetup) {
      evalElement = this;
      props = widget.props?.map<Signal>((prop) {
            if (isSignal(prop)) return prop;
            return signal(prop);
          }).toList() ??
          [];
      render = widget.setup();
      lifecycle.type(LifecycleType.onMounted).call();

      bool effected = false;
      cleanup = effect(() {
        cachedBuiltWidget = render();
        markNeedsBuild();
        effected = true;
      });

      if (!effected) {
        cachedBuiltWidget = render();
      }

      _initializedSetup = true;
    }

    return cachedBuiltWidget;
  }

  @override
  mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    lifecycle.type(LifecycleType.onMounted).call();
  }

  @override
  unmount() {
    lifecycle.type(LifecycleType.onBeforeUnmount).call();
    super.unmount();
    cleanup?.call();
    lifecycle.type(LifecycleType.onUnmounted).call();
  }

  @override
  update(covariant SetupWidget newWidget) {
    lifecycle.type(LifecycleType.onBeforeUpdate).call();

    if (props.isNotEmpty) {
      batch(() {
        for (final (index, prop) in props.indexed) {
          final value = newWidget.props?.elementAtOrNull(index);
          if (isSignal(value)) continue;
          if (prop.peek() == value) continue;

          prop.value = value;
        }
      });
    }

    super.update(newWidget);
    lifecycle.type(LifecycleType.onUpdated).call();
  }

  @override
  activate() {
    super.activate();
    lifecycle.type(LifecycleType.onActivated).call();
  }

  @override
  deactivate() {
    super.deactivate();
    lifecycle.type(LifecycleType.onDeactivated).call();
  }
}

extension on Iterable<Lifecycle> {
  Iterable<Lifecycle> type(LifecycleType type) =>
      where((lifecycle) => lifecycle.type == type);

  void call() {
    for (final lifecycle in this) {
      lifecycle();
    }
  }
}
