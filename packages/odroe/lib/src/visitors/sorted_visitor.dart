import 'package:flutter/widgets.dart';

import '../style_sheet.dart';
import 'style_sheet_visitor.dart';

class SortedVisitor<T extends StyleSheetVisitor>
    implements StyleSheetVisitor, Comparable<SortedVisitor<T>> {
  const SortedVisitor(this.index, this.visitor);

  final int index;
  final T visitor;

  @override
  Widget visit(StyleSheet style, Widget child) => visitor.visit(style, child);

  @override
  int compareTo(SortedVisitor<T> other) {
    if (other.index == index) return 0;
    if (other.index < index) return -1;

    return 1;
  }
}
