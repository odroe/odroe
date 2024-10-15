import 'package:flutter/widgets.dart';

import '../oref_flutter.dart';

/// Creates an observable widget that rebuilds when the [Ref] value changes.
///
/// [ref] - The [Ref] object to observe.
/// [builder] - A function that builds the widget based on the current value of [ref].
/// [key] - An optional key for the widget.
///
/// Returns a Widget that rebuilds whenever the value of [ref] changes.
Widget obs<T>(Ref<T> ref, Widget Function(T value) builder, {Key? key}) {
  return ref.obs(key: key, builder);
}

/// Extension on [Ref] to provide observation capabilities.
extension ObserverRefUtils<T> on Ref<T> {
  /// Creates an observable widget that rebuilds when this [Ref]'s value changes.
  ///
  /// [builder] - A function that builds the widget based on the current value of this [Ref].
  /// [key] - An optional key for the widget.
  ///
  /// Returns a Widget that rebuilds whenever the value of this [Ref] changes.
  Widget obs(Widget Function(T value) builder, {Key? key}) {
    return Builder(
      key: key,
      builder: (context) => builder(value),
    );
  }
}
