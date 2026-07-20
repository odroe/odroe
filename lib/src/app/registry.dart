import 'binding.dart';
import 'key.dart';

/// Collects values and platform bindings while modules are registered.
final class ModuleRegistry {
  /// Creates an empty registry.
  ModuleRegistry();

  final Map<Object, Object> _values = <Object, Object>{};
  final List<ModuleBinding> _bindings = <ModuleBinding>[];

  /// Stores [value] under [key].
  ///
  /// A later module may deliberately replace a value registered earlier.
  void provide<T extends Object>(ContextKey<T> key, T value) {
    _values[key] = value;
  }

  /// Stores a lazily created value under [key].
  ///
  /// The factory runs once, when the application first reads the value.
  void provideFactory<T extends Object>(
    ContextKey<T> key,
    T Function() create,
  ) {
    _values[key] = _Factory<T>(create);
  }

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
