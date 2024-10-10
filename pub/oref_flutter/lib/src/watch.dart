import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'internal/context_scope.dart';
import 'internal/widget_effect.dart';

/// Watches for changes in a computed value and runs a callback when it changes.
///
/// This function sets up a watcher that computes a value of type [T] using the [compute] function,
/// and calls [runner] whenever the computed value changes. The watcher is associated with the given [BuildContext].
///
/// Parameters:
/// - [context]: The BuildContext to associate the watcher with.
/// - [compute]: A function that computes the value to watch.
/// - [runner]: A callback function that is called when the computed value changes.
/// - [immediate]: If true, [runner] is called immediately with the initial value.
/// - [once]: If true, the watcher is automatically disposed after the first change.
///
/// Returns an [oref.WatchHandle] that can be used to manually dispose the watcher.
oref.WatchHandle watch<T extends Record>(
  BuildContext context,
  T Function() compute,
  void Function(T value, T? oldValue) runner, {
  bool immediate = false,
  bool once = false,
}) {
  ensureInitializedWidgetEffect(context);
  final scope = getContextScope(context);
  scope.on();

  try {
    return oncecall(context,
        () => oref.watch<T>(compute, runner, immediate: immediate, once: once));
  } finally {
    scope.off();
  }
}
