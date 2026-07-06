import 'binding.dart';
import 'color.dart';
import 'dimension.dart';
import 'identifier.dart';
import 'mergeable.dart';

/// A partial visual declaration that can be reused and merged.
///
/// An appearance describes what something should look like without saying how
/// any platform should render it. It is the common value that later `Style`
/// declarations will use for roots, parts, and conditional cases.
///
/// ```dart
/// const actionFill = Term<Color>(Identifier('color.action.fill'));
/// const controlRadius = Term<Dimension>(Identifier('radius.control'));
///
/// final control = Appearance(
///   surface: Surface(
///     fill: .term(actionFill),
///     radius: .term(controlRadius),
///   ),
///   metrics: Metrics(
///     padding: Insets.symmetric(
///       x: .literal(16.px),
///       y: .literal(8.px),
///     ),
///   ),
/// );
/// ```
///
/// Appearances are intentionally visual-only. Gestures, navigation, semantic
/// actions, routing, and application behavior belong outside this model.
final class Appearance implements Mergeable<Appearance> {
  /// Creates an appearance from optional visual facets.
  const Appearance({this.surface, this.content, this.metrics});

  /// Surface-facing visual properties such as fills, strokes, and radius.
  final Surface? surface;

  /// Content-facing visual properties such as text and icon color.
  final Content? content;

  /// Size and spacing properties.
  final Metrics? metrics;

  /// Merges this appearance with [later].
  ///
  /// Merge is property-based, not cascade-based. If [later] provides a facet,
  /// that facet is merged with the existing facet. Inside each facet, non-null
  /// properties from [later] replace earlier values and null properties leave
  /// earlier values unchanged.
  @override
  Appearance merge(Appearance later) {
    return Appearance(
      surface: surface.mergedWith(later.surface),
      content: content.mergedWith(later.content),
      metrics: metrics.mergedWith(later.metrics),
    );
  }
}

/// The visual treatment of a surface.
///
/// Surface properties describe the container plane: its fill, outline, radius,
/// and shadow. They deliberately avoid CSS boxes, Flutter decorations, and
/// Material components.
final class Surface implements Mergeable<Surface> {
  /// Creates a partial surface declaration.
  const Surface({this.fill, this.stroke, this.radius, this.shadow});

  /// The surface fill color.
  final Property<Color>? fill;

  /// The stroke or border treatment for the surface.
  final Stroke? stroke;

  /// The corner radius or shape radius for the surface.
  final Property<Dimension>? radius;

  /// The shadow cast by the surface.
  final Property<Shadow>? shadow;

  /// Returns this surface with non-null properties from [later] applied.
  @override
  Surface merge(Surface later) {
    return Surface(
      fill: later.fill ?? fill,
      stroke: stroke.mergedWith(later.stroke),
      radius: later.radius ?? radius,
      shadow: later.shadow ?? shadow,
    );
  }
}

/// The outline treatment of a surface.
///
/// Stroke keeps border-like properties together so a later appearance can
/// override only the color without losing the previously declared width or
/// style. CSS adapters can project this to border properties, while Flutter
/// adapters can project it to `BorderSide`.
final class Stroke implements Mergeable<Stroke> {
  /// Creates a partial stroke declaration.
  const Stroke({this.color, this.width, this.style});

  /// The stroke color.
  final Property<Color>? color;

  /// The stroke width.
  final Property<Dimension>? width;

  /// The stroke style.
  final Property<StrokeStyle>? style;

  /// Returns this stroke with non-null properties from [later] applied.
  @override
  Stroke merge(Stroke later) {
    return Stroke(
      color: later.color ?? color,
      width: later.width ?? width,
      style: later.style ?? style,
    );
  }
}

/// The visual stroke style.
///
/// The core model keeps this deliberately small. Platform adapters can reject
/// unsupported values or map them to the closest target-specific stroke style.
enum StrokeStyle {
  /// A continuous stroke.
  solid,

  /// A dashed stroke.
  dashed,

  /// A dotted stroke.
  dotted,

  /// No visible stroke.
  none,
}

/// A platform-neutral surface shadow.
///
/// A shadow is explicit paint data, not a Material elevation value. Adapter
/// packages can map it to CSS `box-shadow`, Flutter `BoxShadow`, or ignore it
/// when the target does not support shadows.
final class Shadow {
  /// Creates a shadow from zero or more [layers].
  Shadow(Iterable<ShadowLayer> layers) : layers = List.unmodifiable(layers);

  /// The shadow layers, ordered as authored.
  final List<ShadowLayer> layers;

  @override
  bool operator ==(Object other) {
    return other is Shadow && _listEquals(other.layers, layers);
  }

  @override
  int get hashCode => Object.hashAll(layers);
}

/// One layer in a [Shadow].
final class ShadowLayer {
  /// Creates one shadow layer.
  const ShadowLayer({
    required this.color,
    required this.offsetX,
    required this.offsetY,
    required this.blur,
    this.spread = const Dimension.px(0),
  });

  /// The shadow color.
  final Color color;

  /// The horizontal shadow offset.
  final Dimension offsetX;

  /// The vertical shadow offset.
  final Dimension offsetY;

  /// The blur radius.
  final Dimension blur;

  /// The spread radius.
  final Dimension spread;

  @override
  bool operator ==(Object other) {
    return other is ShadowLayer &&
        other.color == color &&
        other.offsetX == offsetX &&
        other.offsetY == offsetY &&
        other.blur == blur &&
        other.spread == spread;
  }

  @override
  int get hashCode => Object.hash(color, offsetX, offsetY, blur, spread);
}

/// The visual treatment of content inside a surface.
///
/// Content properties describe visible children such as labels and icons. They
/// do not describe the child widgets, DOM nodes, accessibility labels, or
/// semantic actions that may eventually use these values.
final class Content implements Mergeable<Content> {
  /// Creates a partial content declaration.
  const Content({this.color, this.text, this.icon, this.opacity});

  /// The foreground color for text or icons.
  final Property<Color>? color;

  /// The semantic text role to use for labels.
  final Property<Identifier>? text;

  /// The semantic icon role to use for icons.
  final Property<Identifier>? icon;

  /// The opacity applied to content.
  final Property<double>? opacity;

  /// Returns this content with non-null properties from [later] applied.
  @override
  Content merge(Content later) {
    return Content(
      color: later.color ?? color,
      text: later.text ?? text,
      icon: later.icon ?? icon,
      opacity: later.opacity ?? opacity,
    );
  }
}

/// Platform-neutral spacing and size values.
///
/// Metrics describe the space a visual object asks for. They are not layout
/// algorithms and do not decide flex, grid, constraints, or widget structure.
final class Metrics implements Mergeable<Metrics> {
  /// Creates a partial metrics declaration.
  const Metrics({
    this.padding,
    this.gap,
    this.width,
    this.height,
    this.minWidth,
    this.minHeight,
    this.maxWidth,
    this.maxHeight,
  });

  /// Space between the outside edge and content.
  final Insets? padding;

  /// Space between repeated children.
  final Property<Dimension>? gap;

  /// The preferred width.
  final Property<Dimension>? width;

  /// The preferred height.
  final Property<Dimension>? height;

  /// The minimum width.
  final Property<Dimension>? minWidth;

  /// The minimum height.
  final Property<Dimension>? minHeight;

  /// The maximum width.
  final Property<Dimension>? maxWidth;

  /// The maximum height.
  final Property<Dimension>? maxHeight;

  /// Returns this metrics declaration with non-null properties from [later]
  /// applied.
  @override
  Metrics merge(Metrics later) {
    return Metrics(
      padding: padding.mergedWith(later.padding),
      gap: later.gap ?? gap,
      width: later.width ?? width,
      height: later.height ?? height,
      minWidth: later.minWidth ?? minWidth,
      minHeight: later.minHeight ?? minHeight,
      maxWidth: later.maxWidth ?? maxWidth,
      maxHeight: later.maxHeight ?? maxHeight,
    );
  }
}

/// A declared value for an appearance property.
///
/// A property is the assignable leaf in an [Appearance]. It either stores a
/// concrete literal value, or it points at a vocabulary [Term] that will be
/// resolved through a [Binding] later.
///
/// Use a literal when the declaration owns the exact value:
///
/// ```dart
/// const surface = Surface(fill: .literal(Color(0xff006adc)));
/// ```
///
/// Use a term when the declaration should follow a shared binding:
///
/// ```dart
/// const fillTerm = Term<Color>(Identifier('color.action.fill'));
///
/// const surface = Surface(fill: .term(fillTerm));
/// ```
sealed class Property<T> {
  /// Creates a property variant.
  const Property();

  /// Creates a property that stores a concrete [value].
  const factory Property.literal(T value) = LiteralProperty<T>;

  /// Creates a property that resolves through [term].
  const factory Property.term(Term<T> term) = TermProperty<T>;
}

/// A [Property] that stores a concrete value in the declaration itself.
///
/// Prefer this variant for values that are intentionally local to an
/// appearance, such as one-off spacing or an override color.
final class LiteralProperty<T> extends Property<T> {
  /// Creates a property from a concrete [value].
  const LiteralProperty(this.value);

  /// The concrete value carried by this property.
  final T value;
}

/// A [Property] that refers to a vocabulary term.
///
/// Prefer this variant when multiple appearances should share the same design
/// decision through a [Binding], such as semantic color or radius terms.
final class TermProperty<T> extends Property<T> {
  /// Creates a property that resolves through [term].
  const TermProperty(this.term);

  /// The referenced term.
  final Term<T> term;
}

/// Four-sided spacing used by [Metrics.padding].
///
/// Each side is optional so padding can participate in appearance merging.
/// Later insets override only the sides they set.
final class Insets implements Mergeable<Insets> {
  /// Creates insets with explicit sides.
  const Insets.only({this.top, this.right, this.bottom, this.left});

  /// Creates equal insets on every side.
  const Insets.all(Property<Dimension> value)
    : top = value,
      right = value,
      bottom = value,
      left = value;

  /// Creates horizontal and vertical insets.
  const Insets.symmetric({Property<Dimension>? x, Property<Dimension>? y})
    : top = y,
      right = x,
      bottom = y,
      left = x;

  /// The top inset.
  final Property<Dimension>? top;

  /// The right inset.
  final Property<Dimension>? right;

  /// The bottom inset.
  final Property<Dimension>? bottom;

  /// The left inset.
  final Property<Dimension>? left;

  /// Returns this inset set with non-null sides from [later] applied.
  @override
  Insets merge(Insets later) {
    return Insets.only(
      top: later.top ?? top,
      right: later.right ?? right,
      bottom: later.bottom ?? bottom,
      left: later.left ?? left,
    );
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }

  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }

  return true;
}
