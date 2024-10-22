import 'dart:async';

import 'package:flutter/widgets.dart';

int _batchDepth = 0;
final _callbacks = <VoidCallback>[];
Completer<void>? _evalCompleter;

void _startBatch() {
  _evalCompleter ??= Completer.sync();
  _batchDepth++;
}

void _endBatch() {
  if ((--_batchDepth) > 0) {
    return;
  }

  final callbacks = List.of(_callbacks, growable: false);
  final completer = _evalCompleter!;

  _callbacks.clear();
  _evalCompleter = null;

  WidgetsFlutterBinding.ensureInitialized().addPostFrameCallback(
    debugLabel: "odroe/setup: next tick",
    (duration) {
      final delayed = Future.delayed(duration);

      completer.complete(delayed);
      unawaited(delayed.then((_) {
        for (final callback in callbacks) {
          callback();
        }
      }));
    },
  );
}

/// Schedules a callback to be executed in the next frame.
///
/// This function batches callbacks to be executed in the next animation frame.
/// If a [callback] is provided, it will be added to the list of callbacks to be executed.
///
/// Returns a [Future] that completes when the next frame is rendered.
Future<void> nextTick([VoidCallback? callback]) {
  _startBatch();
  try {
    if (callback != null) {
      _callbacks.add(callback);
    }

    return _evalCompleter!.future;
  } finally {
    _endBatch();
  }
}
