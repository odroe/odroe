import 'dart:ui' show Color;

final class StyleSheet {
  const StyleSheet({
    this.width,
    this.height,
    this.maxWidth,
    this.maxHeight,
    this.minWidth,
    this.minHeight,
    this.padding,
    this.paddingBottom,
    this.paddingLeft,
    this.paddingRight,
    this.paddingTop,
    this.mergin,
    this.merginTop,
    this.merginRight,
    this.merginBottom,
    this.merginLeft,
  });

  // Sizing ----------------------------------

  final double? width;
  final double? height;

  final double? maxWidth;
  final double? maxHeight;
  final double? minWidth;
  final double? minHeight;

  // Spacing

  final Iterable<double>? padding;
  final double? paddingTop;
  final double? paddingRight;
  final double? paddingBottom;
  final double? paddingLeft;

  final Iterable<double>? mergin;
  final double? merginTop;
  final double? merginRight;
  final double? merginBottom;
  final double? merginLeft;

  // Typography
  final String? fontFamily;
  final Iterable<String>? fontFamilyFallback;
  final String? package;
  final Color? color;

  @override
  int get hashCode {
    return Object.hashAll([
      width,
      height,
      maxWidth,
      maxHeight,
      minWidth,
      minHeight,
      ...?padding,
      paddingTop,
      paddingRight,
      paddingBottom,
      paddingLeft,
      ...?mergin,
      merginTop,
      merginRight,
      merginBottom,
      merginLeft,
    ]);
  }

  @override
  bool operator ==(Object other) {
    return other is StyleSheet && other.hashCode == hashCode;
  }
}
