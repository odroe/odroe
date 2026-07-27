/// One parsed Markdown Components document.
final class MdcDocument {
  /// Creates an immutable document.
  MdcDocument({
    Iterable<MdcNode> nodes = const <MdcNode>[],
    Map<String, Object?> frontmatter = const <String, Object?>{},
  }) : nodes = List<MdcNode>.unmodifiable(nodes),
       frontmatter = _freezeMap(frontmatter);

  /// The document body in source order.
  final List<MdcNode> nodes;

  /// YAML frontmatter normalized to JSON-compatible Dart values.
  final Map<String, Object?> frontmatter;
}

/// A node in an MDC document.
sealed class MdcNode {
  const MdcNode();
}

/// Plain text content.
final class MdcText extends MdcNode {
  /// Creates a text node.
  const MdcText(this.value);

  /// The source text.
  final String value;
}

/// A semantic Markdown element.
final class MdcElement extends MdcNode {
  /// Creates an immutable element.
  MdcElement(
    this.tag, {
    Map<String, String?> attributes = const <String, String?>{},
    Iterable<MdcNode> children = const <MdcNode>[],
  }) : attributes = Map<String, String?>.unmodifiable(attributes),
       children = List<MdcNode>.unmodifiable(children);

  /// The semantic element name, such as `p`, `strong`, or `a`.
  final String tag;

  /// Element attributes produced by Markdown or MDC attribute syntax.
  final Map<String, String?> attributes;

  /// Child nodes in source order.
  final List<MdcNode> children;
}

/// A named component invocation.
final class MdcComponent extends MdcNode {
  /// Creates an immutable component invocation.
  MdcComponent(
    this.name, {
    Map<String, Object?> properties = const <String, Object?>{},
    Iterable<MdcNode> children = const <MdcNode>[],
    Map<String, MdcSlot> slots = const <String, MdcSlot>{},
  }) : properties = _freezeMap(properties),
       children = List<MdcNode>.unmodifiable(children),
       slots = Map<String, MdcSlot>.unmodifiable(slots);

  /// The component name exactly as declared in source.
  final String name;

  /// Typed, JSON-compatible component properties.
  final Map<String, Object?> properties;

  /// The component's default-slot children.
  final List<MdcNode> children;

  /// Explicit named slots keyed by slot name.
  final Map<String, MdcSlot> slots;
}

/// One named component slot.
final class MdcSlot {
  /// Creates an immutable slot.
  MdcSlot({
    Map<String, Object?> properties = const <String, Object?>{},
    Iterable<MdcNode> children = const <MdcNode>[],
  }) : properties = _freezeMap(properties),
       children = List<MdcNode>.unmodifiable(children);

  /// Typed, JSON-compatible slot properties.
  final Map<String, Object?> properties;

  /// Slot children in source order.
  final List<MdcNode> children;
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) =>
    Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final MapEntry(:key, :value) in source.entries)
        key: _freezeValue(value),
    });

Object? _freezeValue(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
    return value;
  }
  if (value is Map<Object?, Object?>) {
    final result = <String, Object?>{};
    for (final MapEntry(:key, :value) in value.entries) {
      if (key is! String) {
        throw ArgumentError.value(key, 'key', 'must be a string');
      }
      result[key] = _freezeValue(value);
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  if (value is Iterable<Object?>) {
    return List<Object?>.unmodifiable(value.map(_freezeValue));
  }
  throw ArgumentError.value(value, 'value', 'must be JSON-compatible');
}
