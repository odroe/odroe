import 'binding.dart';
import 'identifier.dart';

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
///     fill: AppearanceValue.term(actionFill),
///     radius: AppearanceValue.term(controlRadius),
///   ),
///   metrics: Metrics(
///     padding: Insets.symmetric(
///       x: AppearanceValue.literal(Unit.px(16)),
///       y: AppearanceValue.literal(Unit.px(8)),
///     ),
///   ),
/// );
/// ```
///
/// Appearances are intentionally visual-only. Gestures, navigation, semantic
/// actions, routing, and application behavior belong outside this model.
final class Appearance {
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
  Appearance merge(Appearance later) {
    return Appearance(
      surface: switch ((surface, later.surface)) {
        (final current?, final next?) => current.merge(next),
        (final current?, null) => current,
        (null, final next?) => next,
        _ => null,
      },
      content: switch ((content, later.content)) {
        (final current?, final next?) => current.merge(next),
        (final current?, null) => current,
        (null, final next?) => next,
        _ => null,
      },
      metrics: switch ((metrics, later.metrics)) {
        (final current?, final next?) => current.merge(next),
        (final current?, null) => current,
        (null, final next?) => next,
        _ => null,
      },
    );
  }
}

/// The visual treatment of a surface.
///
/// Surface properties describe the container plane: its fill, outline, radius,
/// and elevation. They deliberately avoid CSS boxes, Flutter decorations, and
/// Material components.
final class Surface {
  /// Creates a partial surface declaration.
  const Surface({this.fill, this.stroke, this.radius, this.elevation});

  /// The surface fill color.
  final AppearanceValue<ColorValue>? fill;

  /// The stroke or border color for the surface.
  final AppearanceValue<ColorValue>? stroke;

  /// The corner radius or shape radius for the surface.
  final AppearanceValue<Unit>? radius;

  /// The platform-neutral elevation role or amount.
  final AppearanceValue<Unit>? elevation;

  /// Returns this surface with non-null properties from [later] applied.
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
final class Content {
  /// Creates a partial content declaration.
  const Content({this.color, this.text, this.icon, this.opacity});

  /// The foreground color for text or icons.
  final AppearanceValue<ColorValue>? color;

  /// The semantic text role to use for labels.
  final AppearanceValue<Identifier>? text;

  /// The semantic icon role to use for icons.
  final AppearanceValue<Identifier>? icon;

  /// The opacity applied to content.
  final AppearanceValue<double>? opacity;

  /// Returns this content with non-null properties from [later] applied.
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
final class Metrics {
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
  final AppearanceValue<Unit>? gap;

  /// The preferred width.
  final AppearanceValue<Unit>? width;

  /// The preferred height.
  final AppearanceValue<Unit>? height;

  /// The minimum width.
  final AppearanceValue<Unit>? minWidth;

  /// The minimum height.
  final AppearanceValue<Unit>? minHeight;

  /// The maximum width.
  final AppearanceValue<Unit>? maxWidth;

  /// The maximum height.
  final AppearanceValue<Unit>? maxHeight;

  /// Returns this metrics declaration with non-null properties from [later]
  /// applied.
  Metrics merge(Metrics later) {
    return Metrics(
      padding: switch ((padding, later.padding)) {
        (final current?, final next?) => current.merge(next),
        (final current?, null) => current,
        (null, final next?) => next,
        _ => null,
      },
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

/// A literal appearance value or a reference to a vocabulary term.
///
/// Appearance declarations can use concrete values directly, or defer the value
/// to a [Binding] by referencing a [Term]. Resolution is intentionally not part
/// of this type; a later resolver will choose a binding and replace term
/// references with concrete values.
///
/// ```dart
/// const fill = AppearanceValue.literal(ColorValue.hex(0xff006adc));
/// const fillTerm = Term<ColorValue>(Identifier('color.action.fill'));
/// const referencedFill = AppearanceValue.term(fillTerm);
/// ```
final class AppearanceValue<T> {
  /// Creates a concrete appearance value.
  const AppearanceValue.literal(T value) : literal = value, term = null;

  /// Creates an appearance value that will be read from a binding later.
  const AppearanceValue.term(Term<T> this.term) : literal = null;

  /// The concrete value, when this is a literal value.
  final T? literal;

  /// The referenced term, when this value is binding-backed.
  final Term<T>? term;

  /// Whether this value stores a literal value.
  bool get isLiteral => term == null;

  /// Whether this value references a [Term].
  bool get isTerm => term != null;
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
final class Insets {
  /// Creates insets with explicit sides.
  const Insets.only({this.top, this.right, this.bottom, this.left});

  /// Creates equal insets on every side.
  const Insets.all(AppearanceValue<Unit> value)
    : top = value,
      right = value,
      bottom = value,
      left = value;

  /// Creates horizontal and vertical insets.
  const Insets.symmetric({AppearanceValue<Unit>? x, AppearanceValue<Unit>? y})
    : top = y,
      right = x,
      bottom = y,
      left = x;

  /// The top inset.
  final AppearanceValue<Unit>? top;

  /// The right inset.
  final AppearanceValue<Unit>? right;

  /// The bottom inset.
  final AppearanceValue<Unit>? bottom;

  /// The left inset.
  final AppearanceValue<Unit>? left;

  /// Returns this inset set with non-null sides from [later] applied.
  Insets merge(Insets later) {
    return Insets.only(
      top: later.top ?? top,
      right: later.right ?? right,
      bottom: later.bottom ?? bottom,
      left: later.left ?? left,
    );
  }
}
