// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

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
    Directory? publicDirectory,
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
            : _PublicDirectory(publicDirectory.absolute),
      ),
    );
    return server;
  }

  static Future<void> _listen(
    HttpServer server,
    StartHandler handler,
    _PublicDirectory? publicDirectory,
  ) async {
    await for (final incoming in server) {
      unawaited(_handle(incoming, handler, publicDirectory));
    }
  }

  static Future<void> _handle(
    HttpRequest incoming,
    StartHandler handler,
    _PublicDirectory? publicDirectory,
  ) async {
    try {
      if (await _serveAsset(incoming, publicDirectory)) return;
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
    } on Object {
      try {
        incoming.response.statusCode = 500;
        incoming.response.write('Internal server error.');
      } on StateError {
        // Headers or body have already started.
      }
    } finally {
      await incoming.response.close();
    }
  }

  static Future<bool> _serveAsset(
    HttpRequest request,
    _PublicDirectory? publicDirectory,
  ) async {
    if (publicDirectory == null ||
        !publicDirectory.directory.existsSync() ||
        (request.method != 'GET' && request.method != 'HEAD')) {
      return false;
    }
    final relative = p.joinAll(request.requestedUri.pathSegments);
    if (relative.isEmpty) return false;
    final file = File(
      p.normalize(p.join(publicDirectory.directory.path, relative)),
    );
    if (!p.isWithin(publicDirectory.directory.path, file.path) ||
        !file.existsSync()) {
      return false;
    }
    final publicRoot = await publicDirectory.resolve();
    if (publicRoot == null) return false;
    final resolvedFile = await file.resolveSymbolicLinks();
    if (!p.isWithin(publicRoot, resolvedFile)) return false;

    final length = await file.length();
    request.response
      ..statusCode = HttpStatus.ok
      ..contentLength = length
      ..headers.contentType = _contentType(file.path);
    final name = p.basename(file.path);
    request.response.headers.set(
      HttpHeaders.cacheControlHeader,
      _hasContentHash(name)
          ? 'public, max-age=31536000, immutable'
          : 'no-cache',
    );
    if (request.method != 'HEAD') {
      await request.response.addStream(file.openRead());
    }
    return true;
  }

  static ContentType _contentType(String path) =>
      switch (p.extension(path).toLowerCase()) {
        '.css' => ContentType('text', 'css', charset: 'utf-8'),
        '.html' => ContentType.html,
        '.ico' => ContentType('image', 'x-icon'),
        '.jpeg' || '.jpg' => ContentType('image', 'jpeg'),
        '.js' => ContentType('text', 'javascript', charset: 'utf-8'),
        '.json' => ContentType.json,
        '.png' => ContentType('image', 'png'),
        '.svg' => ContentType('image', 'svg+xml'),
        '.wasm' => ContentType('application', 'wasm'),
        '.webp' => ContentType('image', 'webp'),
        '.woff' => ContentType('font', 'woff'),
        '.woff2' => ContentType('font', 'woff2'),
        _ => ContentType.binary,
      };

  static bool _hasContentHash(String name) => RegExp(
    r'(?:^|[._-])[a-f0-9]{8,}(?:[._-]|$)',
    caseSensitive: false,
  ).hasMatch(name);
}

final class _PublicDirectory {
  _PublicDirectory(this.directory);

  final Directory directory;
  String? _resolved;

  Future<String?> resolve() async {
    final cached = _resolved;
    if (cached != null) return cached;
    if (!directory.existsSync()) return null;
    return _resolved = await directory.resolveSymbolicLinks();
  }
}
