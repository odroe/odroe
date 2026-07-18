/// A node in Odroe's server-rendered semantic HTML tree.
sealed class HtmlNode {
  const HtmlNode();
}

/// Escaped text content.
final class HtmlText extends HtmlNode {
  /// Creates text that is escaped when rendered.
  const HtmlText(this.value);

  /// The unescaped source value.
  final String value;
}

/// One semantic HTML element.
final class HtmlElement extends HtmlNode {
  /// Creates an element.
  const HtmlElement(
    this.tag, {
    this.attributes = const <String, String?>{},
    this.children = const <HtmlNode>[],
  });

  /// The HTML tag name.
  final String tag;

  /// Attribute values. A null value renders a boolean attribute.
  final Map<String, String?> attributes;

  /// Child nodes in document order.
  final List<HtmlNode> children;
}

/// A transparent group of sibling nodes.
final class HtmlFragment extends HtmlNode {
  /// Creates a fragment.
  const HtmlFragment(this.children);

  /// Child nodes in document order.
  final List<HtmlNode> children;
}

/// The insertion point for a matched descendant route document.
final class HtmlOutlet extends HtmlNode {
  /// Creates an outlet.
  const HtmlOutlet();
}
