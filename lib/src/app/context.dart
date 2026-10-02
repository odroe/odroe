import 'dart:async';

import 'binding.dart';
import 'module.dart';
import 'registry.dart';

/// Values and bindings created by an explicit list of application modules.
final class AppContext {
  AppContext._(this._registry, this._modules, {bool settingUp = true})
    : _settingUp = settingUp;

  /// Creates a context without modules for standalone capabilities.
  factory AppContext.empty() =>
      AppContext._(ModuleRegistry(), const <Module>[], settingUp: false);

  final ModuleRegistry _registry;
  final List<Module> _modules;
  bool _settingUp;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  /// Registers and initializes [modules] in declaration order.
  ///
  /// Ownership transfers to the context as each module is yielded. When module
  /// enumeration or any setup phase fails, every installed module is disposed
  /// in reverse order so constructor- and registration-owned resources are not
  /// leaked.
  ///
  /// When setup fails, [onCleanupError] observes each secondary failure while
  /// disposing modules. It cannot replace the original setup error.
  static Future<AppContext> create(
    Iterable<Module> modules, {
    void Function(Object error, StackTrace stackTrace)? onCleanupError,
  }) async {
    final installed = <Module>[];
    final registry = ModuleRegistry();
    final context = AppContext._(registry, installed);
    try {
      for (final module in modules) {
        installed.add(module);
      }
      for (final module in installed) {
        module.register(registry);
      }
      for (final module in installed) {
        await module.initialize(context);
      }
      context._settingUp = false;
      return context;
    } on Object catch (error, stackTrace) {
      try {
        await context._dispose(installed.length, onError: onCleanupError);
      } on Object {
        // Setup is the primary failure presented to the caller.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Reads the value registered under [key].
  T read<T extends Object>(ContextKey<T> key) {
    _ensureActive();
    return _registry.read(key);
  }

  /// Reads a registered value, or returns `null` when it is absent.
  T? maybe<T extends Object>(ContextKey<T> key) {
    _ensureActive();
    return _registry.maybe(key);
  }

  /// Returns an immutable snapshot of bindings assignable to [T], in
  /// registration order.
  Iterable<T> bindings<T extends ModuleBinding>() {
    _ensureActive();
    return List<T>.unmodifiable(_registry.bindings<T>());
  }

  /// Disposes modules in reverse registration order.
  ///
  /// Concurrent and repeated calls return the same future. Already-created
  /// values and bindings remain readable by module cleanup, while uninitialized
  /// lazy factories are sealed. After cleanup settles, every read fails closed.
  Future<void> dispose() {
    if (_settingUp) {
      throw StateError(
        'The application context cannot be disposed during module setup.',
      );
    }
    return _dispose(_modules.length);
  }

  Future<void> _dispose(
    int count, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final current = _disposeFuture;
    if (current != null) return current;

    _registry.sealLazyFactories();
    final completion = Completer<void>();
    _disposeFuture = completion.future;
    unawaited(
      _disposeModules(count, onError: onError).then<void>(
        (_) => completion.complete(),
        onError: (Object error, StackTrace stackTrace) {
          completion.completeError(error, stackTrace);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _disposeModules(
    int count, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      for (var index = count - 1; index >= 0; index--) {
        try {
          await _modules[index].dispose(this);
        } on Object catch (error, stackTrace) {
          try {
            onError?.call(error, stackTrace);
          } on Object {
            // Cleanup reporting cannot replace the primary failure.
          }
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }
    } finally {
      _disposed = true;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  void _ensureActive() {
    if (_disposed) throw StateError('The application context is disposed.');
  }
}
