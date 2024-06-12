import 'style_sheet.dart';

extension StyleSheetUtils on StyleSheet {
  /// On the current basis, create a new [StyleSheet] using [other].
  StyleSheet merge(StyleSheet other) {
    return StyleSheet(
      width: other.width ?? width,
      height: other.height ?? height,
      maxWidth: other.maxWidth ?? maxWidth,
      maxHeight: other.maxHeight ?? maxHeight,
      minWidth: other.minWidth ?? minWidth,
      minHeight: other.minHeight ?? minHeight,
      padding: other.padding ?? padding,
      paddingTop: other.paddingTop ?? paddingTop,
      paddingRight: other.paddingRight ?? paddingRight,
      paddingBottom: other.paddingBottom ?? paddingBottom,
      paddingLeft: other.paddingLeft ?? paddingLeft,
      mergin: other.mergin ?? mergin,
      merginTop: other.merginTop ?? merginTop,
      merginRight: other.merginRight ?? merginRight,
      merginBottom: other.merginBottom ?? merginBottom,
      merginLeft: other.merginLeft ?? merginLeft,
    );
  }
}
