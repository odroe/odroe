import 'package:flutter/widgets.dart';

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
    this.visitor = const DefaultStyleSheetVisitor(),
  }) : assert(child != null && children != null);

  final StyleSheet? style;
  final StyleSheetVisitor visitor;
  final Widget? child;
  final Iterable<Widget>? children;

  StyleSheet _resolveStyle(StyleSheet style) {
    if (this.style != null) {
      return style.merge(this.style!);
    }

    return style;
  }

  @override
  Widget build(BuildContext context) {
    final (themeStyle, _) = OdroeTheme.of(context);
    final style = _resolveStyle(themeStyle);

    final widget = switch ((child, children)) {
      (Widget child, _) => child,
      (null, Iterable<Widget> children) => _ChildrenBox(style, children),
      _ => const SizedBox.shrink(),
    };

    return visitor.visit(style, widget);
  }
}

class _ChildrenBox extends StatelessWidget {
  const _ChildrenBox(this.style, this.children);

  final StyleSheet style;
  final Iterable<Widget> children;

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    throw UnimplementedError();
  }
}
