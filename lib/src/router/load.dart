/// The outcome of one route loader.
final class RouteLoadResult {
  /// Creates a successful loader result.
  const RouteLoadResult.data(this.data)
    : error = null,
      stackTrace = null,
      isLoaded = true;

  /// Creates a failed loader result.
  const RouteLoadResult.error(this.error, this.stackTrace)
    : data = null,
      isLoaded = true;

  /// Marks data that must be loaded by the client runtime.
  const RouteLoadResult.client()
    : data = null,
      error = null,
      stackTrace = null,
      isLoaded = false;

  /// Loader data, when loading succeeded.
  final Object? data;

  /// The loader error, when loading failed.
  final Object? error;

  /// The loader error stack trace.
  final StackTrace? stackTrace;

  /// Whether a loader ran in the runtime that produced this result.
  final bool isLoaded;

  /// Whether loading succeeded.
  bool get hasData => isLoaded && error == null;
}
