import 'dart:async';

import 'http.dart';

/// Observes one unexpected server failure without changing its outcome.
typedef ServerErrorHandler =
    FutureOr<void> Function(
      ServerRequest request,
      Object error,
      StackTrace stackTrace,
    );

/// Reports [error] and observes a synchronous or asynchronous reporter failure.
///
/// The returned future is non-null only when [onError] completes
/// asynchronously and [keepAlive] does not own that future.
Future<void>? reportServerError(
  ServerErrorHandler onError,
  ServerRequest request,
  Object error,
  StackTrace stackTrace, {
  void Function(Future<void> task)? keepAlive,
}) {
  try {
    final report = onError(request, error, stackTrace);
    if (report is! Future<void>) return null;
    final observed = report.then<void>(
      (_) {},
      onError: (Object reporterError, StackTrace reporterStackTrace) {
        _reportReporterFailure(
          request,
          error,
          stackTrace,
          reporterError,
          reporterStackTrace,
        );
      },
    );
    if (keepAlive == null) return observed;
    keepAlive(observed);
  } on Object catch (reporterError, reporterStackTrace) {
    _reportReporterFailure(
      request,
      error,
      stackTrace,
      reporterError,
      reporterStackTrace,
    );
  }
  return null;
}

/// Writes an unexpected failure to the current Dart [Zone].
void defaultServerErrorHandler(
  ServerRequest request,
  Object error,
  StackTrace stackTrace,
) {
  Zone.current.print(
    'Unexpected Odroe server error for '
    '${request.method.wire} ${request.uri.path}: $error\n$stackTrace',
  );
}

void _reportReporterFailure(
  ServerRequest request,
  Object error,
  StackTrace stackTrace,
  Object reporterError,
  StackTrace reporterStackTrace,
) {
  try {
    defaultServerErrorHandler(request, error, stackTrace);
    Zone.current.print(
      'Odroe Server.onError failed: $reporterError\n$reporterStackTrace',
    );
  } on Object {
    // Error reporting must never replace the original outcome.
  }
}
