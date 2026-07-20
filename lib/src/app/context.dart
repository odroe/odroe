import 'dart:async';

import 'binding.dart';
import 'key.dart';
import 'module.dart';
import 'registry.dart';

/// Values and bindings created by an explicit list of application modules.
final class AppContext {
  AppContext._(this._registry, this._modules);

  /// Creates a context without modules for standalone capabilities.
  factory AppContext.empty() =>
      AppContext._(ModuleRegistry(), const <Module>[]);

  final ModuleRegistry _registry;
  final List<Module> _modules;
  bool _disposed = false;

  /// Registers and initializes [modules] in declaration order.
  static Future<AppContext> create(Iterable<Module> modules) async {
    final installed = List<Module>.of(modules, growable: false);
    final registry = ModuleRegistry();
    for (final module in installed) {
      module.register(registry);
    }

    final context = AppContext._(registry, installed);
    var initialized = 0;
    try {
      for (final module in installed) {
        initialized++;
        await module.initialize(context);
      }
      return context;
    } on Object catch (error, stackTrace) {
      try {
        await context._dispose(initialized);
      } on Object {
        // Initialization is the primary failure presented to the caller.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Reads the value registered under [key].
  T read<T extends Object>(ContextKey<T> key) => _registry.read(key);

  /// Reads a registered value, or returns `null` when it is absent.
  T? maybe<T extends Object>(ContextKey<T> key) => _registry.maybe(key);

  /// Returns bindings assignable to [T], in registration order.
  Iterable<T> bindings<T extends ModuleBinding>() => _registry.bindings<T>();

  /// Disposes modules in reverse registration order.
  Future<void> dispose() => _dispose(_modules.length);

  Future<void> _dispose(int count) async {
    if (_disposed) return;
    _disposed = true;
    Object? firstError;
    StackTrace? firstStackTrace;
    for (var index = count - 1; index >= 0; index--) {
      try {
        await _modules[index].dispose(this);
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}
