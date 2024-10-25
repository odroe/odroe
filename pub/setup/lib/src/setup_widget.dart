import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:oref/oref.dart';

// ignore: implementation_imports
import 'package:oref/src/impls/effect.dart' as oref_impl;
// ignore: implementation_imports
import 'package:oref/src/impls/flags.dart' as oref_impl;
// ignore: implementation_imports
import 'package:oref/src/impls/sub.dart' as oref_impl;

import 'global.dart';
import 'helpers/use_widget_ref.dart';
import 'lifecycle.dart';

void _loop() {}

abstract base class SetupElement extends Element {
  SetupElement(SetupWidget super.widget);

  LifecycleHooks get lifecycleHooks;
  Scope get scope;
  Effect<void> get effect;

  @override
  SetupWidget get widget;
}

abstract class SetupWidget extends Widget {
  @literal
  const SetupWidget({super.key, final WidgetRef? ref}) : _widgetRef = ref;

  final WidgetRef? _widgetRef;

  Widget Function() setup();

  @override
  @nonVirtual
  SetupElement createElement() {
    return SetupElementImpl(this);
  }
}

final class SetupElementImpl extends Element implements SetupElement {
  static FlutterErrorDetails reportException(
    DiagnosticsNode context,
    Object exception,
    StackTrace? stack, {
    InformationCollector? informationCollector,
  }) {
    final FlutterErrorDetails details = FlutterErrorDetails(
      exception: exception,
      stack: stack,
      library: 'odroe/setup',
      context: context,
      informationCollector: informationCollector,
    );
    FlutterError.reportError(details);
    return details;
  }

  SetupElementImpl(SetupWidget super.widget) {
    parent = currentElement;
    effect = oref_impl.Effect(_loop, scheduler: scheduler);
    initializeSetup();
  }

  @override
  late final oref_impl.Effect<void> effect;

  @override
  late final LifecycleHooks lifecycleHooks = LifecycleHooks();

  @override
  final Scope scope = createScope(true);

  @override
  bool debugDoingBuild = false;

  @override
  Element? renderObjectAttachingChild;

  @override
  SetupWidget get widget => super.widget as SetupWidget;

  late final Widget Function() build;
  late final SetupElementImpl? parent;
  late Map<Object, Object?>? provides = parent?.provides;

  void initializeSetup() {
    effect.flags |= oref_impl.Flags.allowRecurse | oref_impl.Flags.running;
    oref_impl.cleanupDeps(effect);
    oref_impl.prepareDeps(effect);

    final reset = setCurrentElement(this);
    pauseTracking();

    try {
      build = widget.setup();
    } finally {
      oref_impl.cleanupDeps(effect);
      effect.flags &= ~oref_impl.Flags.running;

      resetTracking();
      reset();
    }
  }

  @override
  void performRebuild() {
    final reset = setCurrentElement(this);
    enableTracking();

    Widget? built;
    try {
      assert(() {
        return debugDoingBuild = true;
      }());

      if (renderObjectAttachingChild != null) {
        pauseTracking();
        try {
          lifecycleHooks(Lifecycle.beforeUpdate);
        } finally {
          resetTracking();
        }
      }

      built = build();
      debugWidgetBuilderValue(widget, built);
    } catch (exception, stack) {
      final details = reportException(
        ErrorDescription('building $this'),
        exception,
        stack,
        informationCollector: () => [
          if (kDebugMode) DiagnosticsDebugCreator(DebugCreator(this)),
        ],
      );
      built = ErrorWidget.builder(details);
    } finally {
      assert(() {
        debugDoingBuild = false;
        return true;
      }());
      reset();
      resetTracking();
      super.performRebuild();
    }

    try {
      final prevRenderAttachingChild = renderObjectAttachingChild;
      renderObjectAttachingChild =
          updateChild(renderObjectAttachingChild, built, slot);
      assert(renderObjectAttachingChild != null);

      if (prevRenderAttachingChild != null) {
        final reset = setCurrentElement(this);
        pauseTracking();
        try {
          lifecycleHooks(Lifecycle.updated);
        } finally {
          reset();
          resetTracking();
        }
      }
    } catch (exception, stack) {
      final details = reportException(
        ErrorDescription('building $this'),
        exception,
        stack,
        informationCollector: () => [
          if (kDebugMode) DiagnosticsDebugCreator(DebugCreator(this)),
        ],
      );
      built = ErrorWidget.builder(details);
      renderObjectAttachingChild = updateChild(null, built, slot);
    }
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    if (renderObjectAttachingChild != null) {
      visitor(renderObjectAttachingChild!);
    }
  }

  @override
  void forgetChild(Element child) {
    assert(child == renderObjectAttachingChild);
    renderObjectAttachingChild = null;
    super.forgetChild(child);
  }

  void scheduler() {
    if (dirty) {
      return;
    } else if ((effect.flags & oref_impl.EffectFlags.active) == 0) {
      if (mounted) {
        return markNeedsBuild();
      }
      return;
    }

    effect.flags |= oref_impl.Flags.running;
    oref_impl.cleanupDeps(effect);
    oref_impl.prepareDeps(effect);

    try {
      if (mounted && !dirty && effect.dirty) {
        markNeedsBuild();
      }
    } finally {
      oref_impl.cleanupDeps(effect);
      effect.flags &= ~oref_impl.Flags.running;
    }
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    final reset = setCurrentElement(this);
    pauseTracking();

    try {
      lifecycleHooks(Lifecycle.beforeMount);
      super.mount(parent, newSlot);
      assert(renderObjectAttachingChild == null);
      rebuild();
      assert(renderObjectAttachingChild != null);
      lifecycleHooks(Lifecycle.mounted);

      final elementRef =
          (widget._widgetRef as WidgetReferenceImpl?)?.elementRef;

      if (elementRef != null && elementRef.value == null) {
        elementRef.value = this;
      }
    } finally {
      reset();
      resetTracking();
    }
  }

  @override
  void unmount() {
    final reset = setCurrentElement(this);
    pauseTracking();

    try {
      lifecycleHooks(Lifecycle.beforeUnmount);
      super.unmount();
      lifecycleHooks(Lifecycle.unmounted);
    } finally {
      scope.stop();
      reset();
      resetTracking();
    }
  }

  @override
  void update(covariant SetupWidget newWidget) {
    super.update(newWidget);
    assert(newWidget == widget);
    rebuild(force: true);

    final elementRef = (widget._widgetRef as WidgetReferenceImpl?)?.elementRef;
    if (elementRef != null) {
      triggerRef(elementRef);
    }
  }

  @override
  void activate() {
    final reset = setCurrentElement(this);
    pauseTracking();

    try {
      super.activate();
      lifecycleHooks(Lifecycle.activated);
    } finally {
      reset();
      resetTracking();
    }
  }

  @override
  void deactivate() {
    final reset = setCurrentElement(this);
    pauseTracking();

    try {
      super.deactivate();
      lifecycleHooks(Lifecycle.deactivated);
    } finally {
      reset();
      resetTracking();
    }
  }
}
