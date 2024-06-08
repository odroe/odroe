import 'package:flutter/widgets.dart';

import '_null_widget.dart';
import 'style_sheet.dart';

typedef NamedStyleSheets = Map<String, StyleSheet>;

abstract interface class OdroeTheme {
  StyleSheet? get style;
  NamedStyleSheets? get sheets;

  const factory OdroeTheme({
    Key? key,
    NamedStyleSheets? sheets,
    StyleSheet? style,
    required Widget child,
  }) = _ThemeImpl;
}

class _ThemeImpl extends StatelessWidget implements OdroeTheme {
  const _ThemeImpl({super.key, this.sheets, this.style, required this.widget});

  @override
  final NamedStyleSheets? sheets;

  @override
  final StyleSheet? style;

  final Widget widget;

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    throw UnimplementedError();
  }
}

// class OdroeTheme {
//   const OdroeTheme._({this.style, this.sheets});

//   final StyleSheet? style;
//   final NamedStyleSheets? sheets;

//   // @override
//   // Widget build(BuildContext context) {
//   //   if (style == null && (sheets == null || sheets?.isEmpty == true)) {
//   //     return child;
//   //   }

//   //   return _ThemeProvider(theme: this, child: child);
//   // }

//   // static StyleSheet? styleMaybeOf(BuildContext context) {
//   //   return context
//   //       .dependOnInheritedWidgetOfExactType<_ThemeProvider>()
//   //       ?.theme
//   //       .style;
//   // }
// }

class _ThemeProvider extends InheritedWidget {
  const _ThemeProvider({required super.child, required this.theme});

  final OdroeTheme theme;

  @override
  bool updateShouldNotify(covariant _ThemeProvider oldWidget) {
    final oldTheme = oldWidget.theme;

    return oldTheme.style != theme.style ||
        oldTheme.sheets?.records.unorderedHashCode !=
            oldTheme.sheets?.records.unorderedHashCode;
  }
}

class OdroeTheme2 extends InheritedWidget {
  const OdroeTheme2({
    required super.child,
    super.key,
    this.style,
    this.sheets = const {},
  });

  final StyleSheet? style;
  final Map<String, StyleSheet> sheets;

  @override
  bool updateShouldNotify(covariant OdroeTheme oldWidget) {
    return oldWidget.style != style ||
        oldWidget.sheets.records.unorderedHashCode !=
            sheets.records.unorderedHashCode;
  }

  @override
  get child => Builder(builder: build);

  Widget build(BuildContext context) {
    const init = (StyleSheet(), <String, StyleSheet>{});
    final theme = _findThemes(context).fold(init, _themesFoldHandle);
  }

  static (StyleSheet, Map<String, StyleSheet>)? of(BuildContext context) {
    const init = (StyleSheet(), <String, StyleSheet>{});
    final theme = _findThemes(context).fold(init, _themesFoldHandle);
  }

  static (StyleSheet, Map<String, StyleSheet>) _themesFoldHandle(
      (StyleSheet, Map<String, StyleSheet>) prev, OdroeTheme theme) {
    final style = switch (theme.style) {};
  }

  static Iterable<OdroeTheme> _findThemes(BuildContext context,
      [Iterable<OdroeTheme> themes = const []]) {
    final element =
        context.getElementForInheritedWidgetOfExactType<OdroeTheme>();
    if (element == null) return themes;

    final results = [element.widget as OdroeTheme, ...themes];
    Element? parent;
    element.visitAncestorElements((element) {
      parent = element;
      return false;
    });

    return switch (parent) {
      Element element => _findThemes(element, results),
      _ => results,
    };
  }
}

extension on Map<String, StyleSheet> {
  Iterable<(String, StyleSheet)> get records =>
      entries.map((e) => (e.key, e.value));
}

extension<T> on Iterable<T> {
  int get unorderedHashCode => Object.hashAllUnordered(this);
}
