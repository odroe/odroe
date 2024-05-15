import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'colors.dart';
import 'theme.dart';
import 'utils.dart';

class ButtonStyle {
  const ButtonStyle({
    this.color,
    this.textSize,
    this.textStyle,
    this.block = false,
    this.padding = const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
    this.disabled = false,
  });

  final OdroeColor? color;
  final double? textSize;
  final TextStyle? textStyle;
  final bool block;
  final EdgeInsetsGeometry padding;
  final bool disabled;

  static const faalback = ButtonStyle(color: Colors.white);
}

class Button extends StatelessWidget {
  const Button({
    super.key,
    this.style,
    required this.text,
    this.onTap,
  });

  final ButtonStyle? style;
  final Text text;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = this.style ?? ButtonStyle.faalback;
    final color = style.color ?? theme.primary;

    Widget widget = DefaultTextStyle(
      textAlign: TextAlign.center,
      style: TextStyle(color: color.onColor),
      child: text,
    );

    if (style.padding.vertical > 0 || style.padding.horizontal > 0) {
      widget = Padding(padding: style.padding, child: widget);
    }

    if (style.disabled != true) {
      widget = _ButtonHoverBackgroud(style: style, child: widget);
      widget = GestureDetector(
        onTap: onTap,
        child: widget,
      );
    } else {
      widget = MouseRegion(
        cursor: SystemMouseCursors.forbidden,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: style.color!.withAlpha(160),
            borderRadius: BorderRadius.circular(theme.rounded[Breakpoint.md]),
          ),
          child: widget,
        ),
      );
    }

    if (!style.block) {
      widget = UnconstrainedBox(child: widget);
    }

    return widget;
  }
}

class _ButtonHoverBackgroud extends StatefulWidget {
  const _ButtonHoverBackgroud({required this.style, required this.child});

  final ButtonStyle style;
  final Widget child;

  @override
  State<_ButtonHoverBackgroud> createState() => _ButtonHoverBackgroudState();
}

class _ButtonHoverBackgroudState extends State<_ButtonHoverBackgroud> {
  bool hover = false;

  Color get color {
    final theme = Theme.of(context);
    final color = widget.style.color ?? theme.primary;
    if (hover) {
      return mixBlackColor(color, .10);
    }

    return color;
  }

  void onHover(PointerHoverEvent _) => setState(() => hover = true);
  void onExit(PointerExitEvent _) => setState(() => hover = false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onHover: onHover,
      onExit: onExit,
      cursor: SystemMouseCursors.click,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(theme.rounded[Breakpoint.md]),
          border: Border.all(color: Color(color.value & 0xffe5e7eb)),
        ),
        child: widget.child,
      ),
    );
  }
}
