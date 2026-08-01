import 'dart:async';

import '../app/context.dart';
import '../app/module.dart';
import '../app/registry.dart';
import 'database.dart';

/// The application context key used to read the configured [SqlDatabase].
final databaseKey = ContextKey<SqlDatabase>('database');

/// Installs one SQL database with explicit resource ownership.
final class DatabaseModule extends Module {
  /// Installs a caller-owned database without closing it on context disposal.
  ///
  /// Use this for request modules that borrow a process-owned connection or
  /// database pool.
  DatabaseModule.borrowed(this.database) : _closeOnDispose = false;

  /// Installs a database that closes when the application context is disposed.
  ///
  /// Do not use this for per-request server modules that share one database.
  DatabaseModule.owned(this.database) : _closeOnDispose = true;

  /// The database registered by this module.
  final SqlDatabase database;

  final bool _closeOnDispose;

  @override
  void register(ModuleRegistry registry) {
    databaseKey.provide(registry, database);
  }

  @override
  FutureOr<void> dispose(AppContext context) {
    if (_closeOnDispose) return database.close();
  }
}
