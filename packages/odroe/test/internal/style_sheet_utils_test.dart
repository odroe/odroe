import 'package:odroe/next/_internal/style_sheet_utils.dart';
import 'package:odroe/next/style_sheet.dart';
import 'package:test/test.dart';

void main() {
  group('InternalStyleSheetUtils', () {
    test('maybeMerge', () {
      const style0 = StyleSheet();
      const style1 = StyleSheet(width: 1);
      const style2 = StyleSheet(height: 1);
      const style3 = StyleSheet(width: 1, height: 1);

      expect(style0.maybeMerge(null), equals(style0));
      expect(style0.maybeMerge(style1), equals(style1));
      expect(style1.maybeMerge(style2), equals(style3));
    });
  });
}
