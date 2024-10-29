import 'package:flutter/widgets.dart';
import 'package:oref/oref.dart';

import '../setup_widget.dart';

/// A widget that rebuilds whenever its builder function returns a different value.
///
/// The [Observer] widget is used to listen to changes in [Ref] values and rebuild
/// the UI when those values change.
class Observer extends SetupWidget {
  /// Creates an [Observer] widget.
  ///
  /// The [builder] function is called whenever a rebuild is needed.
  const Observer(this.builder, {super.key});

  /// The function that builds the widget's content.
  final Widget Function() builder;

  @override
  Widget Function() setup() {
    return () => builder();
  }
}

/// Extension methods for creating observers from [Ref] objects.
extension RefObserverUtils<T> on Ref<T> {
  /// Creates an [Observer] widget that rebuilds when this ref's value changes.
  ///
  /// The [builder] function receives the current value of the ref and returns
  /// a widget.
  SetupWidget obs(Widget Function(T value) builder, {Key? key}) {
    return Observer(key: key, () => builder(value));
  }
}

/// Creates an [Observer] widget for the given [ref].
///
/// This is a convenience function that calls [RefObserverUtils.obs] on the [ref].
SetupWidget obs<T>(Ref<T> ref, Widget Function(T value) builder, {Key? key}) {
  return ref.obs(key: key, builder);
}
