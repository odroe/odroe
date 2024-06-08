class StyleSheet {
  const StyleSheet({this.width, this.height});

  // Sizing ----------------------------------

  final double? width;
  final double? height;

  @override
  int get hashCode => Object.hashAll([width, height]);

  @override
  bool operator ==(Object other) {
    return other is StyleSheet && other.hashCode == hashCode;
  }
}
