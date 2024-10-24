import 'package:flutter/widgets.dart';
import 'package:oref/oref.dart';

import '../setup_widget.dart';

class Observer extends SetupWidget {
  const Observer(this.builder, {super.key});

  final Widget Function() builder;

  @override
  Widget Function() setup() {
    return () => builder();
  }
}

extension RefObserverUtils<T> on Ref<T> {
  SetupWidget obs(Widget Function(T value) builder, {Key? key}) {
    return Observer(key: key, () => builder(value));
  }
}

SetupWidget obs<T>(Ref<T> ref, Widget Function(T value) builder, {Key? key}) {
  return ref.obs(key: key, builder);
}
