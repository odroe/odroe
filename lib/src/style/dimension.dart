/// A platform-neutral measurement used by visual style declarations.
///
/// Dimensions are Odroe's intermediate representation for lengths before a
/// style is projected to CSS, Flutter, or another renderer. A dimension is not
/// layout by itself: responsive selection, container queries, and platform
/// fallback behavior belong to higher-level style resolution.
///
/// ```dart
/// const fixed = Dimension.px(16);
/// final shorthand = 16.px;
/// ```
sealed class Dimension {
  /// Creates a dimension.
  const Dimension();

  /// Creates a logical pixel-like dimension.
  ///
  /// CSS adapters can project this as `px`; Flutter adapters can project this
  /// as logical pixels. Other platforms should map it to their closest
  /// device-independent length.
  const factory Dimension.px(double value) = PixelDimension;
}

/// A logical pixel-like [Dimension].
///
/// This is the only dimension variant currently supported. Additional variants
/// such as percentages or viewport-relative dimensions should be added as
/// explicit subclasses with their own adapter semantics instead of as a unit
/// enum.
final class PixelDimension extends Dimension {
  /// Creates a logical pixel-like dimension.
  const PixelDimension(this.value);

  /// The numeric amount.
  final double value;

  @override
  bool operator ==(Object other) {
    return other is PixelDimension && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

/// Converts numeric literals into dimensions.
///
/// Extension getters are not constant expressions. Use `Dimension.px(16)` when
/// a `const` value is required, and `16.px` when authoring non-const
/// declarations.
extension DimensionNumberExtension on num {
  /// Creates a logical pixel-like dimension from this number.
  Dimension get px => Dimension.px(toDouble());
}
