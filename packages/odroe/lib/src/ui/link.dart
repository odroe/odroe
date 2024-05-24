import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

Widget link(
  String text, {
  TextStyle? style,
  bool disabled = false,
}) {
  defineProps([text, disabled, style]);

  return setup(() {
    final context = useContext();
    final [text, disabled, style] = props();
    final decoration = signal(TextDecoration.none);
    final color = computed(() => switch (disabled.value) {
          true => Theme.of(context).colorScheme.secondaryContainer,
          _ => Theme.of(context).colorScheme.primary,
        });
    final cursor = computed(() => switch (disabled.value) {
          true => SystemMouseCursors.forbidden,
          _ => SystemMouseCursors.click,
        });
    final defaultStyle = computed(() => TextStyle(
          decoration: decoration.value,
          color: color.value,
        ));

    void onHover(_) {
      if (disabled.peek() == false) {
        decoration.value = TextDecoration.underline;
      }
    }

    void onExit(_) {
      if (disabled.peek() == false) {
        decoration.value = TextDecoration.none;
      }
    }

    return () => DefaultTextStyle.merge(
        style: defaultStyle.value,
        child: MouseRegion(
          onEnter: onHover,
          onExit: onExit,
          cursor: cursor.value,
          child: Text(text.value, style: style.value),
        ));
  });
}
