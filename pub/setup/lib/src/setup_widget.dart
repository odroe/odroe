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

/// An [Element] that represents the runtime contract of a [SetupWidget].
///
/// Elements are the instantiation of widgets in the element tree. Element subclasses
/// implement [setup] to define their widget build behavior.
///
/// When a widget is inflated into an element tree, the framework calls the widget's
/// [createElement] method to create an element.
///
/// Provides access to [lifecycleHooks], [scope], and [effect] for managing the element's
/// lifecycle and state.
///
/// This class should not be subclassed directly. Instead, extend [SetupWidget] to
/// create a reusable widget component.
abstract base class SetupElement extends Element {
  /// Creates a new [SetupElement] with the given [widget].
  SetupElement(SetupWidget super.widget);

  /// Lifecycle hooks for managing the element's lifecycle events
  /// like mount, unmount, update etc.
  LifecycleHooks get lifecycleHooks;

  /// The scope associated with this element, used for dependency
  /// tracking and cleanup.
  Scope get scope;

  /// The effect system for this element, which handles reactivity
  /// and dependency tracking.
  Effect<void> get effect;

  @override
  SetupWidget get widget;
}

/// A base widget class that supports reactive setup and lifecycle hooks.
///
/// [SetupWidget] provides a declarative way to create reactive components
/// that automatically track dependencies and update when those dependencies change.
///
/// Subclass [SetupWidget] to create a reusable widget component with:
/// * Reactive state management via [setup] method
/// * Lifecycle hooks for mount/unmount/update events
/// * Dependency injection via widget refs
/// * Automatic cleanup and dependency tracking
///
/// The setup widget lifecycle:
/// 1. Widget is created and [createElement] is called
/// 2. [setup] is invoked to initialize component logic and state
/// 3. Component is mounted and begins tracking dependencies
/// 4. Dependencies update triggers reactive re-rendering
/// 5. Widget unmounts and cleanup runs automatically
///
/// Example:
/// ```dart
/// class MyWidget extends SetupWidget {
///   @override
///   Widget Function() setup() {
///     // Initialize reactive state and effects here
///     return () => Text('Hello');
///   }
/// }
/// ```
abstract class SetupWidget extends Widget {
  /// Creates a [SetupWidget] with an optional [key] and [ref].
  ///
  /// The [ref] parameter allows passing a [WidgetRef] for dependency injection
  /// and state management.
  @literal
  const SetupWidget({super.key, final WidgetRef? ref}) : _widgetRef = ref;

  /// Internal reference to the widget's [WidgetRef] instance.
  final WidgetRef? _widgetRef;

  /// The main setup function that defines the widget's build logic.
  ///
  /// This method is called during widget initialization to set up reactive state
  /// and return a build function that creates the widget's visual representation.
  ///
  /// Returns a function that builds and returns the widget's [Widget] tree.
  Widget Function() setup();

  @override
  @nonVirtual
  SetupElement createElement() {
    final element = SetupElementImpl(this);
    if (_widgetRef != null) {
      element.widgetRefs.add(_widgetRef as WidgetReferenceImpl);
    }

    return element;
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
    provides = parent?.provides;
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
  late final widgetRefs = <WidgetReferenceImpl>{};

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
      batch(() {
        for (final ref in widgetRefs) {
          ref.elementRef.value = this;
        }
      });

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

    try {
      effect.pause();
      batch(() {
        for (final ref in widgetRefs) {
          triggerRef(ref.elementRef);
        }
      });
    } finally {
      effect.resume();
    }

    rebuild(force: true);
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
