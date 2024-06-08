import 'package:flutter/widgets.dart';

import '_internal/map_utils.dart';
import '_internal/style_sheet_utils.dart';
import 'style_sheet.dart';

typedef NamedStyleSheets = Map<String, StyleSheet>;

class OdroeTheme {
  final StyleSheet? style;
  final NamedStyleSheets? sheets;

  const OdroeTheme.value({this.sheets, this.style});

  const factory OdroeTheme(
      {Key? key,
      NamedStyleSheets? sheets,
      StyleSheet? style,
      required Widget child}) = _ThemeWidgetProxy;

  static OdroeTheme? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ThemeProvider>()?.theme;
  }
}

class _ThemeWidgetProxy extends StatelessWidget implements OdroeTheme {
  const _ThemeWidgetProxy(
      {super.key, this.sheets, this.style, required this.child});

  @override
  final NamedStyleSheets? sheets;

  @override
  final StyleSheet? style;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (this.style == null && this.sheets.isNullOrEmpty) {
      return child;
    }

    final parent = OdroeTheme.maybeOf(context);
    final style = parent?.style?.maybeMerge(this.style) ?? this.style;
    final sheets = parent?.sheets?.maybeMerge(this.sheets) ?? this.sheets;

    if (parent?.style == style && sheets.equals(parent?.sheets)) {
      return child;
    }

    return _ThemeProvider(
      theme: OdroeTheme.value(sheets: sheets, style: style),
      child: child,
    );
  }
}

class _ThemeProvider extends InheritedWidget {
  const _ThemeProvider({required super.child, required this.theme});

  final OdroeTheme theme;

  @override
  bool updateShouldNotify(covariant _ThemeProvider oldWidget) {
    return theme.style != oldWidget.theme.style ||
        !theme.sheets.equals(oldWidget.theme.sheets);
  }
}
