// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';

import 'application.dart';
import 'request.dart';

/// Binds an adapter-neutral Start handler to dart:io HttpServer.
final class StartIoServer {
  const StartIoServer._();

  static Future<HttpServer> bind(
    StartHandler handler, {
    Object? address,
    int port = 3000,
    int backlog = 0,
    bool shared = false,
  }) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
      backlog: backlog,
      shared: shared,
    );
    unawaited(_listen(server, handler));
    return server;
  }

  static Future<void> _listen(HttpServer server, StartHandler handler) async {
    await for (final incoming in server) {
      unawaited(_handle(incoming, handler));
    }
  }

  static Future<void> _handle(
    HttpRequest incoming,
    StartHandler handler,
  ) async {
    try {
      final headers = <String, Iterable<String>>{};
      incoming.headers.forEach((name, values) => headers[name] = values);
      final cancelled = Completer<void>();
      unawaited(
        incoming.response.done.whenComplete(() {
          if (!cancelled.isCompleted) cancelled.complete();
        }),
      );
      final request = StartRequest(
        method: StartMethod.parse(incoming.method),
        uri: incoming.requestedUri,
        headers: StartHeaders(headers),
        body: incoming,
        cancelled: cancelled.future,
      );
      final response = await handler(request);
      incoming.response.statusCode = response.status;
      final reason = response.reason;
      if (reason != null) incoming.response.reasonPhrase = reason;
      for (final entry in response.headers.toMap().entries) {
        incoming.response.headers.removeAll(entry.key);
        for (final value in entry.value) {
          incoming.response.headers.add(entry.key, value);
        }
      }
      if (incoming.method != 'HEAD') {
        await incoming.response.addStream(response.body);
      }
    } on Object catch (error) {
      try {
        incoming.response.statusCode = 500;
        incoming.response.write('Start IO adapter failed: $error');
      } on StateError {
        // Headers or body have already started.
      }
    } finally {
      await incoming.response.close();
    }
  }
}
