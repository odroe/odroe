import 'package:flutter/widgets.dart';

import '../style_sheet.dart';
import 'style_sheet_visitor.dart';

class TypographyVisitor implements StyleSheetVisitor {
  const TypographyVisitor();

  @override
  Widget visit(StyleSheet style, Widget widget) {
    (Future.value(1), Future.value(1)).wait;
    return DefaultTextStyle.merge(
      textAlign: style.textAlign,
      overflow: style.textOverflow,
      style: TextStyle(
        package: style.package,
        fontFamily: style.fontFamily,
        fontFamilyFallback: style.fontFamilyFallback,
        color: style.color,
        fontSize: style.fontSize,
        fontStyle: style.fontStyle,
        fontWeight: style.fontWeight,
        letterSpacing: style.letterSpacing,
        height: style.lineHeight,
        decoration: style.textDecorationLine,
        decorationColor: style.textDecorationColor,
        decorationStyle: style.textDecorationStyle,
        decorationThickness: style.textDecorationThickness,
        shadows: style.textShadow,
      ),
      child: widget,
    );
  }
}
