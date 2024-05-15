import 'package:signals_core/signals_core.dart' as signals;

import 'warn.dart';

/// Level is warning, @see https://pub.dev/documentation/logging/latest/logging/Level/WARNING-constant.html
void _warnIsReactive() => warn('Value is already a reactive object');

/// Determine whether a value is a reactive object created by the [reactive] static functions.
bool isReactive(value) =>
    value is signals.MapSignal ||
    value is signals.SetSignal ||
    value is signals.ListSignal;

// ignore: camel_case_types
abstract interface class reactive {
  /// Creates a reactive `Map<K, V>`.
  static Map<K, V> map<K, V>(Map<K, V> value,
      {String? debugLabel, bool autoDispose = false}) {
    if (isReactive(value)) {
      _warnIsReactive();
      return value;
    }

    return signals.MapSignal(value,
        autoDispose: autoDispose, debugLabel: debugLabel);
  }

  /// Creates a reactive `List<T>`.
  static List<T> list<T>(List<T> value,
      {String? debugLabel, bool autoDispose = false}) {
    if (isReactive(value)) {
      _warnIsReactive();
      return value;
    }

    return signals.ListSignal(value,
        autoDispose: autoDispose, debugLabel: debugLabel);
  }

  /// Creates a reactive `Set<T>`.
  static Set<T> set<T>(Set<T> value,
      {String? debugLabel, bool autoDispose = false}) {
    if (isReactive(value)) {
      _warnIsReactive();
      return value;
    }

    return signals.SetSignal(value,
        autoDispose: autoDispose, debugLabel: debugLabel);
  }
}
