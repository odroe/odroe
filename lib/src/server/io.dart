// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';

import '../odroe/server.dart';
import 'development_proxy.dart';
import 'http.dart';
import 'static_files.dart';

/// Binds an adapter-neutral Odroe handler to dart:io.
final class IoServer {
  const IoServer._();

  static Future<HttpServer> bind(
    ServerHandler handler, {
    Object? address,
    int port = 3000,
    int backlog = 0,
    bool shared = false,
    Directory? publicDirectory,
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
        publicDirectory == null ? null : StaticFiles(publicDirectory),
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
      if (await developmentProxy?.serve(incoming) ?? false) return;
      if (await staticFiles?.serve(incoming) ?? false) return;

      final rawHeaders = <String, Iterable<String>>{};
      incoming.headers.forEach((name, values) => rawHeaders[name] = values);
      final cancelled = Completer<void>();
      unawaited(
        incoming.response.done.whenComplete(() {
          if (!cancelled.isCompleted) cancelled.complete();
        }),
      );
      final response = await handler(
        ServerRequest(
          method: HttpMethod.parse(incoming.method),
          uri: incoming.requestedUri,
          headers: Headers(rawHeaders),
          body: incoming,
          cancelled: cancelled.future,
        ),
      );
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
      if (incoming.method != 'HEAD') {
        await incoming.response.addStream(response.body);
      }
    } on Object {
      try {
        incoming.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Internal server error.');
      } on StateError {
        // The response has already started.
      }
    } finally {
      await incoming.response.close();
    }
  }
}
