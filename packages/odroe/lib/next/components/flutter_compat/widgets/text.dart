import 'package:flutter/widgets.dart' as widgets;

import '../../../runtime/fire.dart';
import '../../../runtime/setup.dart';
import '../base_props.dart';

typedef Props = (String value, {widgets.Key? key});

class TextProps extends BaseProps {
  const TextProps(this.text, {super.key, this.style});

  /// @see [widgets.Text.data]
  final String text;

  /// @see [widgets.Text.style]
  final widgets.TextStyle? style;
}

// ignore: non_constant_identifier_names
final Text = setup((TextProps props) {
  return () => fire(() => widgets.Text(
        props.text,
        key: props.key,
        style: props.style,
      ));
});
