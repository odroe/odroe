// ignore_for_file: file_names

import 'style_sheet.dart';

extension StyleSheetMerge on StyleSheet {
  StyleSheet merge(StyleSheet other) {
    return StyleSheet(
      width: other.width ?? width,
      height: other.height ?? height,
    );
  }
}
