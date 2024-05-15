import 'package:flutter/widgets.dart';

import 'colors.dart';
import 'theme.dart';

class ButtonStyle {
  const ButtonStyle({this.color, this.textSize, this.textStyle});

  final OdroeColor? color;
  final double? textSize;
  final TextStyle? textStyle;
}

class Button extends StatelessWidget {
  const Button(
      {super.key,
      this.style,
      required this.text,
      this.onTap,
      this.block = false,
      this.padding = const EdgeInsets.symmetric(vertical: 6, horizontal: 12)});

  final ButtonStyle? style;
  final Text text;
  final void Function()? onTap;
  final bool block;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = style?.color ?? theme.primary;

    Widget widget = DefaultTextStyle(
      textAlign: TextAlign.center,
      style: TextStyle(color: color.onColor),
      child: text,
    );

    if (padding.vertical > 0 || padding.horizontal > 0) {
      widget = Padding(padding: padding, child: widget);
    }

    widget = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
              color: color,
              borderRadius:
                  BorderRadius.circular(theme.rounded[Breakpoint.md])),
          child: widget,
        ),
      ),
    );

    if (!block) {
      widget = UnconstrainedBox(child: widget);
    }

    return widget;
  }
}
