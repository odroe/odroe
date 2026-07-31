import 'binding.dart';

/// A typed key for one value stored in an [AppContext].
final class ContextKey<T extends Object> {
  /// Creates a key with a human-readable [name].
  ///
  /// Keys use instance identity. Keep one key and reuse that exact instance
  /// when providing and reading a value. The name is only for diagnostics.
  ContextKey(this.name);

  /// The name used in diagnostics.
  final String name;

  /// Stores [value] in [registry] under this key.
  ///
  /// A later module may deliberately replace a value registered earlier under
  /// the same key instance.
  void provide(ModuleRegistry registry, T value) {
    registry._values[this] = value;
  }

  /// Stores a lazily created value in [registry] under this key.
  ///
  /// The factory runs once, when the application first reads the value.
  void provideFactory(ModuleRegistry registry, T Function() create) {
    registry._values[this] = _Factory<T>(create);
  }

  @override
  String toString() => 'ContextKey<$T>($name)';
}

/// Collects values and platform bindings while modules are registered.
final class ModuleRegistry {
  /// Creates an empty registry.
  ModuleRegistry();

  final Map<Object, Object> _values = <Object, Object>{};
  final List<ModuleBinding> _bindings = <ModuleBinding>[];

  /// Reads a value already registered under [key].
  T read<T extends Object>(ContextKey<T> key) {
    var value = _values[key];
    if (value == null) {
      throw StateError('No value is registered for ${key.name}.');
    }
    if (value is _Factory<T>) {
      value = value.create();
      _values[key] = value;
    }
    return value as T;
  }

  /// Reads a registered value, or returns `null` when it is absent.
  T? maybe<T extends Object>(ContextKey<T> key) {
    if (!_values.containsKey(key)) return null;
    return read(key);
  }

  /// Adds a platform or capability [binding].
  void bind(ModuleBinding binding) {
    _bindings.add(binding);
  }

  /// Returns registered bindings assignable to [T], in registration order.
  Iterable<T> bindings<T extends ModuleBinding>() => _bindings.whereType<T>();
}

final class _Factory<T extends Object> {
  const _Factory(this.create);

  final T Function() create;
}
