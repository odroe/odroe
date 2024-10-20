import '../impls/batch.dart' as impl;
import './effect.dart' as public;

/// Executes a batch operation.
///
/// This function allows for grouping multiple operations into a single batch.
/// It starts a batch, executes the provided [runner] function, and then ends
/// the batch, ensuring proper cleanup even if an exception occurs.
///
/// [runner] is a function that contains the operations to be executed in the batch.
void batch(void Function() runner) {
  try {
    impl.startBatch();
    runner();
  } finally {
    impl.endBatch();
  }
}

/// Executes a function without tracking its dependencies.
///
/// This function temporarily pauses dependency tracking, executes the provided
/// [runner] function, and then resets tracking. This is useful when you want to
/// perform operations without triggering reactive updates.
///
/// [runner] is a function that returns a value of type [T].
///
/// Returns the result of the [runner] function.
T untracked<T>(T Function() runner) {
  try {
    public.pauseTracking();
    return runner();
  } finally {
    public.resetTracking();
  }
}
