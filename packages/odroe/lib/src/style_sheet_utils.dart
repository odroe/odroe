import 'style_sheet.dart';

extension StyleSheetUtils on StyleSheet {
  /// On the current basis, create a new [StyleSheet] using [other].
  StyleSheet createMergedWith(StyleSheet other) {
    return StyleSheet(
      width: other.width ?? width,
      height: other.height ?? height,
      maxWidth: other.maxWidth ?? maxWidth,
      maxHeight: other.maxHeight ?? maxHeight,
      minWidth: other.minWidth ?? minWidth,
      minHeight: other.minHeight ?? minHeight,
    );
  }
}
