import 'dart:async';

import 'context.dart';
import 'registry.dart';

/// One explicitly selected application capability.
abstract class Module {
  /// Creates a module.
  const Module();

  /// Registers the values and bindings owned by this module.
  void register(ModuleRegistry registry);

  /// Starts work after every module has registered its values.
  FutureOr<void> initialize(AppContext context) {}

  /// Releases resources owned by this module.
  ///
  /// The application owns a module as soon as it is yielded to
  /// `AppContext.create`. This method must therefore tolerate registration or
  /// initialization that did not start or complete.
  FutureOr<void> dispose(AppContext context) {}
}
