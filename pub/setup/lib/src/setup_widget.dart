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
// ignore: implementation_imports
import 'package:oref/src/impls/global.dart' as oref_impl;

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
  const SetupWidget({super.key, @mustBeConst final Symbol? ref})
      : widgetRefKey = ref;

  final Symbol? widgetRefKey;
  Widget Function() setup();

  @override
  @nonVirtual
  SetupElement createElement() {
    return _SetupElement(this);
  }
}

final class _SetupElement extends Element implements SetupElement {
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

  _SetupElement(SetupWidget super.widget) {
    parent = currentElement;
    if (widget.widgetRefKey != null && parent != null) {
      setWidgetRef(parent!, widget.widgetRefKey!, widget);
    }
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
  late final SetupElement? parent;

  @override
  void performRebuild() {
    final reset = setCurrentElement(this);
    enableTracking();

    Widget? built;
    try {
      assert(() {
        return debugDoingBuild = true;
      }());

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
      super.performRebuild();
      reset();
      resetTracking();
    }

    try {
      renderObjectAttachingChild =
          updateChild(renderObjectAttachingChild, built, slot);
      assert(renderObjectAttachingChild != null);
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
      if (kDebugMode && oref_impl.activeSub != effect) {
        debugPrint('setup: Active effect was not restored correctly');
      }

      oref_impl.cleanupDeps(effect);
      effect.flags &= ~oref_impl.Flags.running;
    }
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    pauseTracking();
    final reset = setCurrentElement(this);

    try {
      effect = oref_impl.Effect(_loop, scheduler: scheduler);
      effect.flags |= oref_impl.Flags.allowRecurse | oref_impl.Flags.running;

      oref_impl.cleanupDeps(effect);
      oref_impl.prepareDeps(effect);

      final prevSub = oref_impl.activeSub;
      enableTracking();
      oref_impl.activeSub = effect;

      try {
        build = widget.setup();
      } finally {
        oref_impl.cleanupDeps(effect);
        oref_impl.activeSub = prevSub;
        resetTracking();
        effect.flags &= ~oref_impl.Flags.running;
      }

      lifecycleHooks(Lifecycle.beforeMount);
      super.mount(parent, newSlot);
      assert(renderObjectAttachingChild == null);
      rebuild();
      assert(renderObjectAttachingChild != null);
      lifecycleHooks(Lifecycle.mounted);
    } finally {
      reset();
      resetTracking();
    }
  }

  @override
  void unmount() {
    //
    super.unmount();
  }

  @override
  void update(covariant SetupWidget newWidget) {
    lifecycleHooks(Lifecycle.beforeUpdate);
    if (parent != null &&
        widget != newWidget &&
        newWidget.widgetRefKey != null &&
        Widget.canUpdate(widget, newWidget)) {
      setWidgetRef(parent!, newWidget.widgetRefKey!, newWidget,
          trigger: !dirty);
      setWidgetRef(this, SetupElementSymbol(this), newWidget, trigger: !dirty);
    }

    super.update(newWidget);
    lifecycleHooks(Lifecycle.updated);
  }

  @override
  void activate() {
    super.activate();
    lifecycleHooks(Lifecycle.activated);
  }

  @override
  void deactivate() {
    super.deactivate();
    lifecycleHooks(Lifecycle.deactivated);
  }
}
