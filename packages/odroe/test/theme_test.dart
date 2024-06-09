import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/next/theme.dart';

void main() {
  testWidgets("not provide theme", (tester) async {
    final themes = tester.allElements.map((e) => OdroeTheme.maybeOf(e));
    expect(themes, equals(tester.allElements.map((_) => null)));
  });

  testWidgets("provide", (tester) async {
    const theme = OdroeTheme(child: SizedBox.shrink());
    await tester.pumpWidget(theme);
  });
}
