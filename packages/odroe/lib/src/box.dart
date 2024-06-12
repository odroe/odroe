import 'package:flutter/widgets.dart';

import 'style.dart';
import 'style_sheet.dart';
import 'style_sheet_utils.dart';
import 'visitors/default_style_sheet_visitor.dart';
import 'visitors/style_sheet_visitor.dart';

class Box extends StatelessWidget {
  const Box({
    super.key,
    this.child,
    this.children,
    this.style,
    this.aspect,
    this.visitor = const DefaultStyleSheetVisitor(),
  })  : assert(child != null || children != null),
        assert(style != null || aspect?.length != 0);

  final StyleSheet? style;
  final StyleSheetVisitor visitor;
  final Widget? child;
  final Iterable<Widget>? children;
  final String? aspect;

  @override
  Widget build(BuildContext context) {
    final style = switch (aspect) {
      String aspect when aspect.isNotEmpty => Style.maybeOf(context, aspect),
      _ => null,
    };

    final effectStyle = switch (this.style) {
      StyleSheet current => style?.merge(current) ?? current,
      _ => style,
    };

    final widget = switch ((child, children)) {
      (Widget child, _) => child,
      (null, Iterable<Widget> children) => _ChildrenBox(style, children),
      _ => const SizedBox.shrink(),
    };

    return switch (effectStyle) {
      StyleSheet style => visitor.visit(style, widget),
      _ => widget,
    };
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
