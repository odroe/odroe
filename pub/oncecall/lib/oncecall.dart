import 'package:_octr/_octr.dart';
import 'package:flutter/widgets.dart';

final _evalCount = findOrCreateExpando<int>();
final _memoirzed = findOrCreateExpando<Map<int, dynamic>>();

/// Executes a function once per frame and memoizes its result.
///
/// This function ensures that the provided [fn] is called only once per frame
/// and returns the memoized result for subsequent calls within the same frame.
///
/// Parameters:
/// - [context]: The BuildContext used to track the evaluation count.
/// - [fn]: The function to be executed and memoized.
///
/// Returns:
/// The result of [fn], either freshly computed or retrieved from memoization.
T oncecall<T>(BuildContext context, T Function() fn) {
  WidgetsFlutterBinding.ensureInitialized().addPostFrameCallback((_) {
    _evalCount[context] = null;
  });

  final count = _evalCount[context] ??= 0;
  final memoirzed = _memoirzed[context] ??= <int, dynamic>{};
  final value = memoirzed[count];

  _evalCount[context] = count + 1;
  if (value is T && memoirzed.containsKey(count)) {
    return value;
  }

  return memoirzed[count] = fn();
}
