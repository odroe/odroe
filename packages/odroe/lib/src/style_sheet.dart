import 'package:flutter/widgets.dart';

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
    this.color,
    this.fontFamily,
    this.fontFamilyFallback,
    this.fontSize,
    this.fontStyle,
    this.fontWeight,
    this.letterSpacing,
    this.lineHeight,
    this.package,
    this.textAlign,
    this.textDecorationColor,
    this.textDecorationLine,
    this.textDecorationStyle,
    this.textDecorationThickness,
    this.textOverflow,
    this.textShadow,
  });

  // Sizing

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
  final List<String>? fontFamilyFallback;
  final String? package;
  final Color? color;
  final double? fontSize;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final double? letterSpacing;
  final double? lineHeight;
  final TextDecoration? textDecorationLine;
  final Color? textDecorationColor;
  final TextDecorationStyle? textDecorationStyle;
  final double? textDecorationThickness;
  final TextAlign? textAlign;
  final TextOverflow? textOverflow;
  final List<Shadow>? textShadow;

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
      fontFamily,
      ...?fontFamilyFallback,
      package,
      color,
      fontSize,
      fontWeight,
      letterSpacing,
      lineHeight,
      textDecorationLine,
      textDecorationColor,
      textDecorationStyle,
      textDecorationThickness,
      textAlign,
      textOverflow,
      textShadow,
    ]);
  }

  @override
  bool operator ==(Object other) {
    return other is StyleSheet && other.hashCode == hashCode;
  }
}
