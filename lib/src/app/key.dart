/// A typed key for one value stored in an [AppContext].
final class ContextKey<T extends Object> {
  /// Creates a key with a human-readable [name].
  const ContextKey(this.name);

  /// The name used in diagnostics.
  final String name;

  @override
  String toString() => 'ContextKey<$T>($name)';
}
