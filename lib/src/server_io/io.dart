import 'dart:async';
import 'dart:io';

import '../server/server.dart';
import 'development_proxy.dart';
import '../server/http.dart';
import 'static_files.dart';

/// Binds an adapter-neutral Odroe handler to dart:io.
final class IoServer {
  const IoServer._();

  /// Starts an HTTP server that forwards requests to [handler].
  ///
  /// Files in [publicDirectory] use conditional caching and stream eligible
  /// responses with gzip when [compressStaticAssets] is enabled. Exact files
  /// take priority; HTML-compatible requests fall back to an `index.html`
  /// below the requested path.
  static Future<HttpServer> bind(
    ServerHandler handler, {
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
    unawaited(
      _listen(
        server,
        handler,
        publicDirectory == null
            ? null
            : StaticFiles(publicDirectory, compress: compressStaticAssets),
        developmentProxyOriginFile == null
            ? null
            : DevelopmentProxy(developmentProxyOriginFile.absolute),
      ),
    );
    return server;
  }

  static Future<void> _listen(
    HttpServer server,
    ServerHandler handler,
    StaticFiles? staticFiles,
    DevelopmentProxy? developmentProxy,
  ) async {
    try {
      await for (final incoming in server) {
        unawaited(_handle(incoming, handler, staticFiles, developmentProxy));
      }
    } finally {
      developmentProxy?.close();
    }
  }

  static Future<void> _handle(
    HttpRequest incoming,
    ServerHandler handler,
    StaticFiles? staticFiles,
    DevelopmentProxy? developmentProxy,
  ) async {
    try {
      late final HttpMethod method;
      try {
        method = HttpMethod.parse(incoming.method);
      } on FormatException {
        incoming.response.statusCode = HttpStatus.notImplemented;
        return;
      }
      if (await staticFiles?.serve(incoming, indexFallback: false) ?? false) {
        return;
      }
      if (await developmentProxy?.serve(incoming) ?? false) return;
      if (await staticFiles?.serve(incoming) ?? false) return;

      final rawHeaders = <String, Iterable<String>>{};
      incoming.headers.forEach((name, values) => rawHeaders[name] = values);
      final cancelled = Completer<void>();
      unawaited(
        incoming.response.done.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {
            if (!cancelled.isCompleted) cancelled.complete();
          },
        ),
      );
      final response = await handler(
        ServerRequest(
          method: method,
          uri: incoming.requestedUri,
          headers: Headers(rawHeaders),
          body: incoming,
          cancelled: cancelled.future,
        ),
      );
      try {
        incoming.response.statusCode = response.status;
        if (response.reason case final reason?) {
          incoming.response.reasonPhrase = reason;
        }
        for (final entry in response.headers.entries) {
          incoming.response.headers.removeAll(entry.key);
          for (final value in entry.value) {
            incoming.response.headers.add(entry.key, value);
          }
        }
      } on Object catch (error, stackTrace) {
        final subscription = response.body.listen(null);
        await subscription.cancel();
        Error.throwWithStackTrace(error, stackTrace);
      }
      final omitBody =
          incoming.method == 'HEAD' ||
          response.status < 200 ||
          response.status == HttpStatus.noContent ||
          response.status == HttpStatus.resetContent ||
          response.status == HttpStatus.notModified;
      if (omitBody) {
        final subscription = response.body.listen(null);
        await subscription.cancel();
      } else {
        await incoming.response.addStream(response.body);
      }
    } on Object {
      try {
        incoming.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Internal server error.');
      } on Object {
        // The response has already started or the client disconnected.
      }
    } finally {
      try {
        await incoming.response.close();
      } on Object {
        // Closing a disconnected response is already complete from our side.
      }
    }
  }
}
