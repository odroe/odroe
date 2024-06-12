import 'package:flutter/widgets.dart';

import 'pattern_style.dart';
import 'style_sheet.dart';

class Style extends StatelessWidget {
  const Style({this.style, this.pattern, this.named, super.key});

  final StyleSheet? style;
  final Iterable<PatternStyle>? pattern;
  final Map<String, StyleSheet>? named;

  @override
  Widget build(BuildContext context) {
    // final parentTextStyle = DefaultTextStyle.merge(…)

    // TODO: implement build
    throw UnimplementedError();
  }

  // StyleSheet of(BuildContext context, {String? aspect}) {
  //   // const basic = StyleSheet();
  //   context.dependOnInheritedWidgetOfExactType<_StyleProvider>();
  }
}

class _StyleProvider extends InheritedWidget {
  const _StyleProvider({required super.child});

  @override
  bool updateShouldNotify(covariant _StyleProvider oldWidget) {
    // TODO: implement updateShouldNotify
    throw UnimplementedError();
  }
}
