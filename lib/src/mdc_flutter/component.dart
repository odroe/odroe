import 'package:flutter/widgets.dart';

import '../mdc/component.dart';

/// Builds the Flutter representation of an MDC component.
typedef MdcWidgetComponentBuilder =
    Widget Function(MdcWidgetComponentContext context);

/// A component available to Flutter MDC renderers.
final class MdcWidgetComponent implements MdcComponentBinding {
  /// Creates a named Flutter component.
  const MdcWidgetComponent(this.name, this.builder);

  @override
  final String name;

  /// Builds the component from parsed properties and rendered slots.
  final MdcWidgetComponentBuilder builder;

  @override
  Type get rendererType => MdcWidgetComponent;
}

/// The input passed to an [MdcWidgetComponentBuilder].
final class MdcWidgetComponentContext {
  /// Creates a Flutter component context.
  const MdcWidgetComponentContext({
    required this.context,
    required this.name,
    required this.properties,
    required this.children,
    required this.slots,
  });

  /// The active Flutter build context.
  final BuildContext context;

  /// The component name found in the source document.
  final String name;

  /// The component properties parsed from MDC source.
  final Map<String, Object?> properties;

  /// The rendered default slot.
  final Widget children;

  /// The rendered named slots.
  final Map<String, MdcWidgetSlot> slots;
}

/// One rendered named slot passed to a Flutter component.
final class MdcWidgetSlot {
  /// Creates a rendered named slot.
  const MdcWidgetSlot({required this.properties, required this.children});

  /// Properties declared on the slot.
  final Map<String, Object?> properties;

  /// The rendered slot content.
  final Widget children;
}
