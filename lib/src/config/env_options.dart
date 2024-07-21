import 'dart:io';

/// Environment options.
abstract class EnvOptions {
  /// The directory from which `.env` files are loaded.
  ///
  /// Can be an absolute path, or a path relative to the project root.
  ///
  /// Defaults to `<root>`
  abstract Directory dir;

  /// A prefix that signals that an environment variable is safe to expose to client-side code.
  ///
  /// Env variables starting with env prefix will be exposed to your
  /// client source code via `String.fromEnvironment`.
  ///
  /// Defaults to `PUBLIC_`.
  String publicPrefix = 'PUBLIC_';
}
