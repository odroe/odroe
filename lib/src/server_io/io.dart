import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../server/error_reporter.dart';
import '../server/http.dart';
import '../server/server.dart';
import 'development_proxy.dart';
import 'static_files.dart';

/// Binds an adapter-neutral Odroe handler to dart:io.
final class IoServer {
  const IoServer._();

  static final Expando<_IoServerLifecycle> _lifecycles =
      Expando<_IoServerLifecycle>('Odroe IO server lifecycle');

  /// Starts an HTTP server that forwards requests to [handler].
  ///
  /// Files in [publicDirectory] use conditional caching and stream eligible
  /// responses with gzip when [compressStaticAssets] is enabled. Exact files
  /// take priority; HTML-compatible requests fall back to an `index.html`
  /// below the requested path.
  ///
  /// [onError] reports unexpected failures owned by this adapter, including
  /// static files, the development proxy, response metadata, framing, and
  /// omitted response bodies from raw handlers. Handler and source-stream
  /// failures remain owned by [handler]. The default writes to the current
  /// Dart Zone; pass an explicit no-op to disable reporting. The callback
  /// starts after the server-side response close attempt settles. Its future is
  /// observed by the detached request task, which [HttpServer.close] does not
  /// await, so keep reporting bounded and use an application-owned durable
  /// queue when delivery must survive shutdown.
  static Future<HttpServer> bind(
    ServerHandler handler, {
    ServerErrorHandler? onError,
    Object? address,
    int port = 3000,
    int backlog = 0,
    bool shared = false,
    Directory? publicDirectory,
    bool compressStaticAssets = true,
    File? developmentProxyOriginFile,
  }) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
      backlog: backlog,
      shared: shared,
    );
    final lifecycle = _IoServerLifecycle();
    _lifecycles[server] = lifecycle;
    final listening = _listen(
      server,
      handler,
      onError ?? defaultServerErrorHandler,
      publicDirectory == null
          ? null
          : StaticFiles(publicDirectory, compress: compressStaticAssets),
      developmentProxyOriginFile == null
          ? null
          : DevelopmentProxy(developmentProxyOriginFile.absolute),
      lifecycle,
    );
    lifecycle.listening = listening;
    unawaited(
      listening.then<void>((_) {}, onError: _reportDetachedTaskFailure),
    );
    return server;
  }

  /// Stops [server] and waits for every accepted request task to settle.
  ///
  /// Unlike [HttpServer.close], this includes the detached adapter work that
  /// writes and closes responses and reports failures. Concurrent and repeated
  /// calls for a server returned by [bind] share one future. A later
  /// `force: true` call escalates an earlier graceful close.
  static Future<void> close(HttpServer server, {bool force = false}) {
    final lifecycle = _lifecycles[server];
    if (lifecycle == null) return server.close(force: force);
    return lifecycle.close(server, force: force);
  }

  static Future<void> _listen(
    HttpServer server,
    ServerHandler handler,
    ServerErrorHandler onError,
    StaticFiles? staticFiles,
    DevelopmentProxy? developmentProxy,
    _IoServerLifecycle lifecycle,
  ) async {
    try {
      await for (final incoming in server) {
        lifecycle.track(
          _handle(incoming, handler, onError, staticFiles, developmentProxy),
        );
      }
    } finally {
      await lifecycle.drain();
      developmentProxy?.close();
    }
  }

  static Future<void> _handle(
    HttpRequest incoming,
    ServerHandler handler,
    ServerErrorHandler onError,
    StaticFiles? staticFiles,
    DevelopmentProxy? developmentProxy,
  ) async {
    ServerRequest? request;
    HttpMethod? requestMethod;
    _PendingReport? pendingReport;
    var hadPrimaryFailure = false;

    try {
      late final HttpMethod method;
      try {
        method = HttpMethod.parse(incoming.method);
      } on FormatException {
        incoming.response.statusCode = HttpStatus.notImplemented;
        return;
      }
      requestMethod = method;
      late final Uri requestedUri;
      try {
        requestedUri = incoming.requestedUri;
      } on FormatException {
        _writeBadRequest(incoming, method);
        return;
      } on Object catch (error, stackTrace) {
        hadPrimaryFailure = true;
        pendingReport = (request: null, error: error, stackTrace: stackTrace);
        _writeInternalServerError(incoming, method);
        return;
      }

      try {
        if (await staticFiles?.serve(incoming, indexFallback: false) ?? false) {
          return;
        }
        if (await developmentProxy?.serve(incoming) ?? false) return;
        if (await staticFiles?.serve(incoming) ?? false) return;
      } on Object catch (error, stackTrace) {
        hadPrimaryFailure = true;
        pendingReport ??= _diagnosticFailure(
          incoming,
          method,
          error,
          stackTrace,
        );
        _writeInternalServerError(incoming, method);
        return;
      }

      final cancelled = Completer<void>();
      unawaited(
        incoming.response.done.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {
            if (!cancelled.isCompleted) cancelled.complete();
          },
        ),
      );
      try {
        request = ServerRequest(
          method: method,
          uri: requestedUri,
          headers: _headers(incoming),
          body: incoming,
          cancelled: cancelled.future,
        );
      } on FormatException {
        _writeBadRequest(incoming, method);
        return;
      } on Object catch (error, stackTrace) {
        hadPrimaryFailure = true;
        pendingReport = (request: null, error: error, stackTrace: stackTrace);
        _writeInternalServerError(incoming, method);
        return;
      }

      late final ServerResponse response;
      try {
        response = await handler(request);
      } on Object {
        hadPrimaryFailure = true;
        _writeInternalServerError(incoming, method);
        return;
      }

      final omitBody =
          method == HttpMethod.head ||
          response.status < 200 ||
          response.status == HttpStatus.noContent ||
          response.status == HttpStatus.resetContent ||
          response.status == HttpStatus.notModified;
      final statusForbidsFraming =
          response.status < 200 || response.status == HttpStatus.noContent;
      final resetContent = response.status == HttpStatus.resetContent;
      final notModifiedWithoutHead =
          response.status == HttpStatus.notModified &&
          method != HttpMethod.head;
      final discardContentFraming =
          statusForbidsFraming || resetContent || notModifiedWithoutHead;
      try {
        incoming.response.statusCode = response.status;
        if (response.reason case final reason?) {
          incoming.response.reasonPhrase = reason;
        }
        for (final entry in response.headers.entries) {
          if (discardContentFraming &&
              (entry.key == HttpHeaders.contentLengthHeader ||
                  entry.key == HttpHeaders.transferEncodingHeader)) {
            continue;
          }
          incoming.response.headers.removeAll(entry.key);
          if (entry.key == HttpHeaders.transferEncodingHeader) {
            incoming.response.headers.chunkedTransferEncoding = false;
          }
          for (final value in entry.value) {
            incoming.response.headers.add(entry.key, value);
          }
        }
        if (discardContentFraming) {
          incoming.response.headers.chunkedTransferEncoding = false;
        }
        if (resetContent) incoming.response.contentLength = 0;
      } on Object catch (error, stackTrace) {
        hadPrimaryFailure = true;
        await _cancelResponseBody(response.body);
        pendingReport ??= (
          request: request,
          error: error,
          stackTrace: stackTrace,
        );
        _writeInternalServerError(incoming, method);
        return;
      }
      if (omitBody) {
        final cancellationFailure = await _cancelResponseBody(response.body);
        if (cancellationFailure case final failure?) {
          hadPrimaryFailure = true;
          pendingReport ??= (
            request: request,
            error: failure.error,
            stackTrace: failure.stackTrace,
          );
        }
        if (method != HttpMethod.head &&
            (statusForbidsFraming || notModifiedWithoutHead)) {
          try {
            await incoming.response.addStream(const Stream<List<int>>.empty());
          } on Object catch (error, stackTrace) {
            hadPrimaryFailure = true;
            if (!_isTransportDisconnect(error)) {
              pendingReport ??= (
                request: request,
                error: error,
                stackTrace: stackTrace,
              );
            }
          }
        }
      } else {
        var sourceFailed = false;
        final body = response.body.transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleError: (error, stackTrace, sink) {
              sourceFailed = true;
              sink.addError(error, stackTrace);
            },
          ),
        );
        try {
          await incoming.response.addStream(body);
        } on Object catch (error, stackTrace) {
          hadPrimaryFailure = true;
          if (!sourceFailed && !_isTransportDisconnect(error)) {
            pendingReport ??= (
              request: request,
              error: error,
              stackTrace: stackTrace,
            );
          }
          _writeInternalServerError(incoming, method);
        }
      }
    } finally {
      try {
        await incoming.response.close();
      } on Object catch (error, stackTrace) {
        final currentRequest = request;
        if (!hadPrimaryFailure && !_isTransportDisconnect(error)) {
          if (currentRequest != null) {
            pendingReport ??= (
              request: currentRequest,
              error: error,
              stackTrace: stackTrace,
            );
          } else if (requestMethod case final method?) {
            pendingReport ??= _diagnosticFailure(
              incoming,
              method,
              error,
              stackTrace,
            );
          }
        }
      }
      if (pendingReport case final failure?) {
        if (failure.request case final reportRequest?) {
          final reportDone = reportServerError(
            onError,
            reportRequest,
            failure.error,
            failure.stackTrace,
          );
          if (reportDone != null) await reportDone;
        } else {
          _reportWithoutRequest(incoming, failure.error, failure.stackTrace);
        }
      }
    }
  }
}

final class _IoServerLifecycle {
  late final Future<void> listening;

  final Set<Future<void>> _active = <Future<void>>{};
  Future<void>? _closeFuture;
  bool _forceRequested = false;

  void track(Future<void> task) {
    late final Future<void> observed;
    observed = task.then<void>(
      (_) => _active.remove(observed),
      onError: (Object error, StackTrace stackTrace) {
        _active.remove(observed);
        _reportDetachedTaskFailure(error, stackTrace);
      },
    );
    _active.add(observed);
  }

  Future<void> drain() async {
    while (_active.isNotEmpty) {
      await Future.wait<void>(List<Future<void>>.of(_active));
    }
  }

  Future<void> close(HttpServer server, {required bool force}) {
    final current = _closeFuture;
    if (current != null) {
      if (force && !_forceRequested) {
        _forceRequested = true;
        unawaited(
          server
              .close(force: true)
              .then<void>((_) {}, onError: _reportDetachedTaskFailure),
        );
      }
      return current;
    }

    _forceRequested = force;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    unawaited(
      _close(server, force: force).then<void>(
        (_) => completion.complete(),
        onError: (Object error, StackTrace stackTrace) {
          completion.completeError(error, stackTrace);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _close(HttpServer server, {required bool force}) async {
    Object? primaryError;
    StackTrace? primaryStackTrace;
    try {
      await server.close(force: force);
    } on Object catch (error, stackTrace) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    }
    try {
      await listening;
    } on Object catch (error, stackTrace) {
      if (primaryError == null) {
        primaryError = error;
        primaryStackTrace = stackTrace;
      } else {
        _reportDetachedTaskFailure(error, stackTrace);
      }
    }
    if (primaryError != null) {
      Error.throwWithStackTrace(primaryError, primaryStackTrace!);
    }
  }
}

typedef _PendingReport = ({
  ServerRequest? request,
  Object error,
  StackTrace stackTrace,
});

Headers _headers(HttpRequest request) {
  final raw = <String, Iterable<String>>{};
  request.headers.forEach((name, values) => raw[name] = values);
  return Headers(raw);
}

ServerRequest _diagnosticRequest(HttpRequest request, HttpMethod method) =>
    ServerRequest(method: method, uri: request.uri, headers: _headers(request));

_PendingReport _diagnosticFailure(
  HttpRequest request,
  HttpMethod method,
  Object error,
  StackTrace stackTrace,
) {
  try {
    return (
      request: _diagnosticRequest(request, method),
      error: error,
      stackTrace: stackTrace,
    );
  } on Object {
    return (request: null, error: error, stackTrace: stackTrace);
  }
}

Future<({Object error, StackTrace stackTrace})?> _cancelResponseBody(
  Stream<List<int>> body,
) async {
  try {
    await body.listen(null, onError: (Object _, StackTrace _) {}).cancel();
    return null;
  } on Object catch (error, stackTrace) {
    return (error: error, stackTrace: stackTrace);
  }
}

void _writeBadRequest(HttpRequest request, HttpMethod method) {
  _writeErrorResponse(
    request,
    method,
    status: HttpStatus.badRequest,
    reason: 'Bad Request',
    bytes: _badRequestBody,
  );
}

void _writeInternalServerError(HttpRequest request, HttpMethod method) {
  _writeErrorResponse(
    request,
    method,
    status: HttpStatus.internalServerError,
    reason: 'Internal Server Error',
    bytes: _internalServerErrorBody,
  );
}

void _writeErrorResponse(
  HttpRequest request,
  HttpMethod method, {
  required int status,
  required String reason,
  required List<int> bytes,
}) {
  try {
    final response = request.response;
    response.headers.clear();
    response.cookies.clear();
    response
      ..statusCode = status
      ..reasonPhrase = reason
      ..persistentConnection = false
      ..contentLength = bytes.length;
    response.headers.contentType = ContentType.text;
    if (method != HttpMethod.head) response.add(bytes);
  } on Object {
    // The response has already started or the client disconnected.
  }
}

void _reportWithoutRequest(
  HttpRequest request,
  Object error,
  StackTrace stackTrace,
) {
  try {
    Zone.current.print(
      'Unexpected Odroe IO adapter error for '
      '${request.method} ${request.uri.path}: $error\n$stackTrace',
    );
  } on Object {
    // Error reporting must never replace the original outcome.
  }
}

void _reportDetachedTaskFailure(Object error, StackTrace stackTrace) {
  try {
    Zone.current.print(
      'Unexpected detached Odroe IO adapter error: $error\n$stackTrace',
    );
  } on Object {
    // Error reporting must never replace adapter cleanup.
  }
}

bool _isTransportDisconnect(Object error) =>
    error is SocketException || error is TlsException;

final List<int> _badRequestBody = utf8.encode('Bad request.');
final List<int> _internalServerErrorBody = utf8.encode(
  'Internal server error.',
);
