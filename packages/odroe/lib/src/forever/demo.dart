import 'package:flutter/widgets.dart';

import 'component.dart';
import 'props.dart';

demo(String name) {
  defineProps([name]);

  return setup(() {
    final [demo] = props();

    return () => fire(Text(name));
  });
}
