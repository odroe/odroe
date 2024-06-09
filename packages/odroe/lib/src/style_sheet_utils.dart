import 'style_sheet.dart';
import '_internal/pattern_utils.dart';

extension StyleSheetUtils on StyleSheet {
  /// On the current basis, create a new [StyleSheet] using [other].
  StyleSheet createWith(StyleSheet other, [Pattern? pattern]) {
    return StyleSheet(
      pattern: pattern,
      width: other.width ?? width,
      height: other.height ?? height,
      maxWidth: other.maxWidth ?? maxWidth,
      maxHeight: other.maxHeight ?? maxHeight,
      minWidth: other.minWidth ?? minWidth,
      minHeight: other.minHeight ?? minHeight,
    );
  }

  /// Create or return another with equal patterns.
  ///
  /// If the pattern of other matches the current pattern,
  /// create a new StyleSheet using [other] on top of the
  /// current StyleSheet. Otherwise, return to other.
  StyleSheet createOrAnother(StyleSheet other) {
    return switch (pattern.equals(other.pattern)) {
      true => createWith(other, pattern),
      _ => other,
    };
  }
}
