import 'package:flutter/widgets.dart';
import 'package:oref/oref.dart';

import '../setup_widget.dart';

class Observer extends SetupWidget {
  const Observer({super.key, required this.builder});

  final Widget Function() builder;

  @override
  Widget Function() setup() {
    return () => builder();
  }
}

extension RefObserverUtils<T> on Ref<T> {
  SetupWidget obs(Widget Function() builder, {Key? key}) {
    return Observer(key: key, builder: builder);
  }
}

SetupWidget obs<T>(Ref<T> ref, Widget Function() builder, {Key? key}) {
  return ref.obs(key: key, builder);
}
