class StyleSheet {
  const StyleSheet({
    this.pattern,
    this.cascades,
    this.width,
    this.height,
    this.maxWidth,
    this.maxHeight,
    this.minWidth,
    this.minHeight,
  });

  // Baisc
  final Pattern? pattern;
  final Iterable<StyleSheet>? cascades;

  // Sizing ----------------------------------

  final double? width;
  final double? height;

  final double? maxWidth;
  final double? maxHeight;
  final double? minWidth;
  final double? minHeight;

  @override
  int get hashCode {
    return Object.hashAll([
      ...?cascades,
      pattern,
      width,
      height,
      maxWidth,
      maxHeight,
      minWidth,
      minHeight,
    ]);
  }

  @override
  bool operator ==(Object other) {
    return other is StyleSheet && other.hashCode == hashCode;
  }
}
