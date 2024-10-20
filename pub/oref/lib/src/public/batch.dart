import '../impls/batch.dart' as impl;

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
