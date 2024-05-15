import 'package:flutter/widgets.dart';

import 'style_sheet/style_sheet.dart';

class Box extends StatelessWidget {
  const Box({super.key, this.sheets = const [], this.child});

  final Iterable<StyleSheet> sheets;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
