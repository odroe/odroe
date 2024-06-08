// ignore_for_file: file_names

import '../style_sheet.dart';
import '../style_sheet+merge.dart';

extension InternalStyleSheetUtils on StyleSheet {
  StyleSheet maybeMerge(StyleSheet? other) {
    if (other != null) {
      return merge(other);
    }

    return this;
  }
}
