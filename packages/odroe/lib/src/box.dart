import 'package:flutter/widgets.dart';

import '_internal/map_utils.dart';
import '_internal/style_sheet_utils.dart';
import 'style_sheet.dart';
import 'theme.dart';
import 'visitors/default_style_sheet_visitor.dart';
import 'visitors/style_sheet_visitor.dart';

class Box extends StatelessWidget {
  const Box({
    super.key,
    this.child,
    this.children,
    this.style,
    this.sheets,
    this.visitor = const DefaultStyleSheetVisitor(),
  }) : assert(child != null && children != null);

  final StyleSheet? style;
  final Iterable<String>? sheets;
  final StyleSheetVisitor visitor;
  final Widget? child;
  final Iterable<Widget>? children;

  @override
  Widget build(BuildContext context) {
    final parent = OdroeTheme.maybeOf(context);
    final currentStyle = parent?.style?.maybeMerge(this.style) ?? this.style;
    final StyleSheet? namedStyle = switch (sheets) {
      Iterable(isNotEmpty: true, contains: final contains) => parent?.sheets
          ?.where((name, _) => contains(name))
          .values
          .fold(null, (prev, current) => prev?.maybeMerge(current) ?? current),
      _ => null,
    };

    final style = namedStyle?.maybeMerge(currentStyle) ?? currentStyle;
    final widget = switch ((child, children)) {
      (Widget child, _) => child,
      (null, Iterable<Widget> children) => _ChildrenBox(style, children),
      _ => const SizedBox.shrink(),
    };

    if (style == null) return widget;

    return visitor.visit(style, widget);
  }
}

class _ChildrenBox extends StatelessWidget {
  const _ChildrenBox(this.style, this.children);

  final StyleSheet? style;
  final Iterable<Widget> children;

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    throw UnimplementedError();
  }
}
