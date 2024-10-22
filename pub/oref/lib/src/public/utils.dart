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

/// Enables precise type inference for function return types.
///
/// Acts as an identity function for functions, allowing the Dart analyzer
/// to infer the specific return type of the passed function. This is particularly
/// useful in reactive contexts where complex return types may be challenging
/// for Dart's type system to infer accurately.
///
/// ## Usage
///
/// Use this function when you want to leverage Dart's type inference capabilities
/// without explicitly declaring types, especially for complex return types.
///
/// Example:
/// ```dart
/// // Without inferReturnType, type might be inferred as dynamic.
/// hello() => (name: "seven", age: 30);
///
/// // Without inferReturnType, violate lint rules
/// final hello = () => (name: "seven", age: 30);
///
///
/// // With inferReturnType:
/// final hello = inferReturnType(() => (name: "seven", age: 30));
/// // Specific return type is correctly inferred
/// ```
///
/// By using `inferReturnType`, you can maintain code clarity and benefit from
/// precise type inference in your development environment without sacrificing
/// the advantages of Dart's type system.
///
/// > [!IMPORTANT]
/// > inferReturnType is effective when the return type is Record and is complex. It is not recommended for other types.
F inferReturnType<F extends Function>(F fn) => fn;
