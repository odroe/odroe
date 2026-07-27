import '../app/binding.dart';
import '../document/node.dart';

/// A named component contributed to one MDC renderer.
abstract interface class MdcComponentBinding implements ModuleBinding {
  /// The component name used by MDC source.
  String get name;

  /// Identifies the renderer that consumes this binding.
  Type get rendererType;
}

/// Thrown when a renderer cannot resolve a component used by a document.
final class MdcUnknownComponentException implements Exception {
  /// Creates an unknown-component exception.
  const MdcUnknownComponentException(this.name);

  /// The unresolved component name.
  final String name;

  @override
  String toString() => 'No MDC component is registered for "$name".';
}

/// Builds the HTML representation of an MDC component.
typedef MdcHtmlComponentBuilder =
    HtmlNode Function(MdcHtmlComponentContext context);

/// A component available to the MDC HTML renderer.
final class MdcHtmlComponent implements MdcComponentBinding {
  /// Creates a named HTML component.
  const MdcHtmlComponent(this.name, this.builder);

  @override
  final String name;

  /// Builds the component from parsed properties and rendered slots.
  final MdcHtmlComponentBuilder builder;

  @override
  Type get rendererType => MdcHtmlComponent;
}

/// The input passed to an [MdcHtmlComponentBuilder].
final class MdcHtmlComponentContext {
  /// Creates an HTML component context.
  const MdcHtmlComponentContext({
    required this.name,
    required this.properties,
    required this.children,
    required this.slots,
  });

  /// The component name found in the source document.
  final String name;

  /// The component properties parsed from MDC source.
  final Map<String, Object?> properties;

  /// The rendered default slot.
  final HtmlFragment children;

  /// The rendered named slots.
  final Map<String, MdcHtmlSlot> slots;
}

/// One rendered named slot passed to an HTML component.
final class MdcHtmlSlot {
  /// Creates a rendered named slot.
  const MdcHtmlSlot({required this.properties, required this.children});

  /// Properties declared on the slot.
  final Map<String, Object?> properties;

  /// The rendered slot content.
  final HtmlFragment children;
}
