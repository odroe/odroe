import 'package:flutter/widgets.dart';

import 'style_sheet.dart';
import 'style_sheet_utils.dart';

class Style extends StatelessWidget {
  const Style({super.key, required this.child, required this.style});

  final StyleSheet style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = maybeOf(context)?.createOrAnother(this.style) ?? this.style;

    // If style is an empty [StyleSheet], it is not provided.
    if (style == const StyleSheet()) {
      return child;
    }

    return _StyleProvider(style, child);
  }

  static StyleSheet? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_StyleProvider>()?.style;
  }
}

class _StyleProvider extends InheritedWidget {
  const _StyleProvider(this.style, Widget child) : super(child: child);

  final StyleSheet style;

  @override
  bool updateShouldNotify(covariant _StyleProvider oldWidget) {
    return oldWidget.style != style;
  }
}
