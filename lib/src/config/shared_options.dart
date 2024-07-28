import 'dart:io';

/// Odroe application mode.
enum OdroeMode { development, production }

/// Odroe shared options.
abstract class SharedOptions {
  /// Project root directory.
  ///
  /// Can be an absolute path, or a path relative to the current working directory.
  ///
  /// Defaults to `Directory.current`.
  abstract Directory root;

  /// Base public path when served in development or production.
  ///
  /// Defaults to '/'.
  String base = '/';

  /// Specifying this in config will override the default mode for both serve and build.
  ///
  /// Default: `development` for dev, `production` for build.
  abstract OdroeMode mode;

  /// Define an environment declaration.
  ///
  /// @see Dart CLI `--define` option.
  final define = <String, String>{};

  /// Odroe application routes directory.
  ///
  /// Defaults to `<root>/routes`.
  abstract Directory routes;
}
