import 'package:flutter/widgets.dart';

class Style {
  const Style({
    this.size,
    this.constraints,
    this.padding,
    this.mergin,
    this.decoration,
    this.text,
    this.alignment,
  });

  final Size? size;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? mergin;
  final BoxDecoration? decoration;
  final TextStyle? text;
  final AlignmentGeometry? alignment;

  @override
  get hashCode => Object.hash(
      size, constraints, padding, mergin, decoration, text, alignment);

  @override
  bool operator ==(Object other) {
    return other is Style && other.hashCode == hashCode;
  }
}
