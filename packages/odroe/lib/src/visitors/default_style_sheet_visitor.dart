import 'package:flutter/widgets.dart';

import '../style_sheet.dart';
import 'sizing/size_visitor.dart';
import 'sorted_visitor.dart';
import 'spacing/mergin_visitor.dart';
import 'spacing/padding_visitor.dart';
import 'style_sheet_visitor.dart';
import 'typography_visitor.dart';

const _defailtVisitors = <StyleSheetVisitor>[
  MerginVisitor(),
  SizeVisitor(),
  PaddingVisitor(),
  TypographyVisitor(),
];

class DefaultStyleSheetVisitor implements StyleSheetVisitor {
  const DefaultStyleSheetVisitor();

  Iterable<StyleSheetVisitor> get visitors => _defailtVisitors;

  @override
  Widget visit(StyleSheet style, Widget widget) {
    return visitors
        .sorted()
        .fold(widget, (widget, visitor) => visitor.visit(style, widget));
  }
}

extension on Iterable<SortedVisitor> {
  Iterable<SortedVisitor> sorted() =>
      List.of(this)..sort((prev, current) => prev.compareTo(current));
}

extension on Iterable<StyleSheetVisitor> {
  Iterable<SortedVisitor> sorted() => indexed.map(wrap).sorted();

  SortedVisitor wrap((int index, StyleSheetVisitor visitor) element) {
    return switch (element.$2) {
      SortedVisitor visitor => visitor,
      _ => SortedVisitor(element.$1, element.$2),
    };
  }
}
