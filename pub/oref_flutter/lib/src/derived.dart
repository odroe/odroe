import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'internal/context_scope.dart';
import 'internal/widget_effect.dart';

/// Creates a derived value based on a getter function.
///
/// This function creates a [oref.Derived] value that is computed using the provided [getter] function.
/// The derived value is automatically updated whenever its dependencies change.
///
/// Parameters:
///   - [context]: The [BuildContext] used for widget-specific operations.
///   - [getter]: A function that computes and returns the derived value.
///
/// Returns:
///   A [oref.Derived] instance representing the derived value.
oref.Derived<T> derived<T>(BuildContext context, T Function() getter) {
  ensureInitializedWidgetEffect(context);
  final scope = getContextScope(context);

  scope.on();
  try {
    return oncecall(context, () => oref.derived(getter));
  } finally {
    scope.off();
  }
}

/// Extension on the derived function to provide additional utility methods for creating derived values.
///
/// This extension adds methods for creating writable and valuable derived values,
/// which offer more flexibility and functionality compared to the basic derived values.
extension FlutterGlobalDerivedUtils on oref.Derived<T> Function<T>(
    BuildContext, T Function()) {
  /// Creates a writable derived value based on a getter and setter function.
  ///
  /// This method creates a [oref.Derived] value that can be both read and written to.
  /// The value is computed using the [getter] function and can be updated using the [setter] function.
  ///
  /// Parameters:
  ///   - [context]: The [BuildContext] used for widget-specific operations.
  ///   - [getter]: A function that computes and returns the derived value.
  ///   - [setter]: A function that updates the derived value.
  ///
  /// Returns:
  ///   A writable [oref.Derived] instance representing the derived value.

  /// Creates a valuable derived value based on a getter function.
  ///
  /// This method creates a [oref.Derived] value that can be read and automatically
  /// updates when its dependencies change. The value is computed using the [getter] function.
  ///
  /// Parameters:
  ///   - [context]: The [BuildContext] used for widget-specific operations.
  ///   - [getter]: A function that computes and returns the derived value.
  ///
  /// Returns:
  ///   A valuable [oref.Derived] instance representing the derived value.
  oref.Derived<T> writable<T>(
    BuildContext context,
    T Function(T? oldValue) getter,
    void Function(T newValue) setter,
  ) {
    ensureInitializedWidgetEffect(context);
    final scope = getContextScope(context);

    scope.on();
    try {
      return oncecall(context, () => oref.derived.writable(getter, setter));
    } finally {
      scope.off();
    }
  }

  /// Creates a valuable derived value based on a getter function.
  ///
  /// This method creates a [oref.Derived] value that can be read and automatically
  /// updates when its dependencies change. The value is computed using the [getter] function.
  ///
  /// Parameters:
  ///   - [context]: The [BuildContext] used for widget-specific operations.
  ///   - [getter]: A function that computes and returns the derived value.
  ///
  /// Returns:
  ///   A valuable [oref.Derived] instance representing the derived value.
  oref.Derived<T> valuable<T>(
      BuildContext context, T Function(T? oldValue) getter) {
    ensureInitializedWidgetEffect(context);
    final scope = getContextScope(context);

    scope.on();
    try {
      return oncecall(context, () => oref.derived.valuable(getter));
    } finally {
      scope.off();
    }
  }
}
