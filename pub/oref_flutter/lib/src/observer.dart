import 'package:flutter/widgets.dart';

import '../oref_flutter.dart';
import 'internal/context_scope.dart';
import 'internal/widget_effect.dart';

/// A widget that automatically rebuilds when observed reactive state changes.
///
/// This widget is used to create a reactive section of your UI that will
/// automatically update whenever any reactive state it depends on changes.
///
/// Usage:
/// ```dart
/// Observer(
///   builder: (context) {
///     return Text(count.value.toString());
///   },
/// )
/// ```
///
/// The [builder] function will be re-run whenever any reactive state
/// accessed within it changes, causing the widget to rebuild.
class Observer extends StatelessWidget {
  /// Creates an [Observer] widget.
  ///
  /// The [builder] parameter is required and should be a function that returns
  /// the widget tree to be built reactively.
  ///
  /// The [key] parameter is optional and can be used to control how one widget replaces
  /// another widget in the tree.
  const Observer({super.key, required this.builder});

  /// The builder function that returns the widget tree to be built reactively.
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    ensureInitializedWidgetEffect(context);
    final scope = getContextScope(context);
    scope.on();

    try {
      return builder(context);
    } finally {
      scope.off();
    }
  }
}

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
    return Observer(
      key: key,
      builder: (_) => builder(value),
    );
  }
}
