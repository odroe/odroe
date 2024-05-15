import 'package:flutter/widgets.dart';

import 'colors.dart';
import 'theme.dart';

enum AlertVariant { solid, outline, soft, subtle }

class AlertStyle {
  const AlertStyle({
    required this.color,
    this.variant = AlertVariant.solid,
  });

  final OdroeColor color;
  final AlertVariant variant;

  AlertStyle merge(AlertStyle style) {
    return AlertStyle(
      color: style.color,
      variant: style.variant,
    );
  }

  static const fallback = AlertStyle(color: Colors.white);
}

class Alert extends StatelessWidget {
  const Alert({super.key, this.style, this.title});

  final AlertStyle? style;
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = switch (this.style) {
      AlertStyle style => theme.alert.merge(style),
      _ => theme.alert,
    };

    final textColor = style.color.onColor;
    final bgColor = style.color;
    final borderColor = Color.lerp(bgColor, textColor, 0.1)!;
    final titleStyle = TextStyle(color: textColor);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(theme.rounded[Breakpoint.lg]),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Text(
          'hjakhsdjka',
          style: titleStyle,
        ),
      ),
    );
  }
}
