import 'binding.dart';
import 'identifier.dart';
import 'mergeable.dart';

/// A partial visual declaration that can be reused and merged.
///
/// An appearance describes what something should look like without saying how
/// any platform should render it. It is the common value that later `Style`
/// declarations will use for roots, parts, and conditional cases.
///
/// ```dart
/// const actionFill = Term<ColorValue>(Identifier('color.action.fill'));
/// const controlRadius = Term<Unit>(Identifier('radius.control'));
///
/// final control = Appearance(
///   surface: Surface(
///     fill: .term(actionFill),
///     radius: .term(controlRadius),
///   ),
///   metrics: Metrics(
///     padding: Insets.symmetric(
///       x: .literal(Unit.px(16)),
///       y: .literal(Unit.px(8)),
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
/// and elevation. They deliberately avoid CSS boxes, Flutter decorations, and
/// Material components.
final class Surface implements Mergeable<Surface> {
  /// Creates a partial surface declaration.
  const Surface({this.fill, this.stroke, this.radius, this.elevation});

  /// The surface fill color.
  final Property<ColorValue>? fill;

  /// The stroke or border color for the surface.
  final Property<ColorValue>? stroke;

  /// The corner radius or shape radius for the surface.
  final Property<Unit>? radius;

  /// The platform-neutral elevation role or amount.
  final Property<Unit>? elevation;

  /// Returns this surface with non-null properties from [later] applied.
  @override
  Surface merge(Surface later) {
    return Surface(
      fill: later.fill ?? fill,
      stroke: later.stroke ?? stroke,
      radius: later.radius ?? radius,
      elevation: later.elevation ?? elevation,
    );
  }
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
  final Property<ColorValue>? color;

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
  final Property<Unit>? gap;

  /// The preferred width.
  final Property<Unit>? width;

  /// The preferred height.
  final Property<Unit>? height;

  /// The minimum width.
  final Property<Unit>? minWidth;

  /// The minimum height.
  final Property<Unit>? minHeight;

  /// The maximum width.
  final Property<Unit>? maxWidth;

  /// The maximum height.
  final Property<Unit>? maxHeight;

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
/// const surface = Surface(fill: .literal(ColorValue.hex(0xff006adc)));
/// ```
///
/// Use a term when the declaration should follow a shared binding:
///
/// ```dart
/// const fillTerm = Term<ColorValue>(Identifier('color.action.fill'));
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

/// A platform-neutral 32-bit ARGB color.
///
/// The integer layout matches `0xAARRGGBB`. This value does not depend on
/// Flutter's `Color`, CSS color strings, or browser parsing rules.
final class ColorValue {
  /// Creates a color from a 32-bit ARGB integer.
  const ColorValue.hex(this.argb)
    : assert(argb >= 0),
      assert(argb <= 0xffffffff);

  /// The `0xAARRGGBB` color value.
  final int argb;

  @override
  bool operator ==(Object other) {
    return other is ColorValue && other.argb == argb;
  }

  @override
  int get hashCode => argb.hashCode;
}

/// The unit used by a [Unit] value.
enum UnitKind {
  /// A logical pixel-like unit.
  ///
  /// Platform adapters decide how this maps to their own coordinate systems.
  px,
}

/// A platform-neutral scalar size.
///
/// Units are declaration values, not layout constraints. They can describe
/// spacing, radius, gaps, and other visual metrics without naming a rendering
/// toolkit.
final class Unit {
  /// Creates a logical pixel-like size.
  const Unit.px(this.value) : kind = UnitKind.px;

  /// The numeric amount.
  final double value;

  /// The unit used by [value].
  final UnitKind kind;

  @override
  bool operator ==(Object other) {
    return other is Unit && other.value == value && other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(value, kind);
}

/// Four-sided spacing used by [Metrics.padding].
///
/// Each side is optional so padding can participate in appearance merging.
/// Later insets override only the sides they set.
final class Insets implements Mergeable<Insets> {
  /// Creates insets with explicit sides.
  const Insets.only({this.top, this.right, this.bottom, this.left});

  /// Creates equal insets on every side.
  const Insets.all(Property<Unit> value)
    : top = value,
      right = value,
      bottom = value,
      left = value;

  /// Creates horizontal and vertical insets.
  const Insets.symmetric({Property<Unit>? x, Property<Unit>? y})
    : top = y,
      right = x,
      bottom = y,
      left = x;

  /// The top inset.
  final Property<Unit>? top;

  /// The right inset.
  final Property<Unit>? right;

  /// The bottom inset.
  final Property<Unit>? bottom;

  /// The left inset.
  final Property<Unit>? left;

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
