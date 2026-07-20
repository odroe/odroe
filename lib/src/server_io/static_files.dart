import 'dart:io';

import 'package:path/path.dart' as p;

/// Serves one contained public directory for the IO adapter.
final class StaticFiles {
  /// Creates a server for files contained by [directory].
  StaticFiles(Directory directory) : directory = directory.absolute;

  /// The public directory served by this instance.
  final Directory directory;
  final Map<String, File> _files = <String, File>{};
  String? _resolvedRoot;

  /// Serves [request] when it resolves to a public file.
  Future<bool> serve(HttpRequest request) async {
    if (!directory.existsSync() ||
        (request.method != 'GET' && request.method != 'HEAD')) {
      return false;
    }
    final relative = p.joinAll(request.requestedUri.pathSegments);
    if (relative.isEmpty) return false;
    final file = await _file(relative);
    if (file == null) return false;

    request.response
      ..statusCode = HttpStatus.ok
      ..contentLength = await file.length()
      ..headers.contentType = _contentType(file.path);
    request.response.headers.set(
      HttpHeaders.cacheControlHeader,
      _contentHash.hasMatch(p.basename(file.path))
          ? 'public, max-age=31536000, immutable'
          : 'no-cache',
    );
    if (request.method != 'HEAD') {
      await request.response.addStream(file.openRead());
    }
    return true;
  }

  Future<File?> _file(String relative) async {
    final cached = _files[relative];
    if (cached != null) return cached;
    final path = p.normalize(p.join(directory.path, relative));
    if (!p.isWithin(directory.path, path)) return null;
    final candidate = File(path);
    if (!candidate.existsSync()) return null;
    final root = await _root();
    if (root == null) return null;
    final resolved = await candidate.resolveSymbolicLinks();
    if (!p.isWithin(root, resolved)) return null;
    return _files[relative] = File(resolved);
  }

  Future<String?> _root() async {
    final cached = _resolvedRoot;
    if (cached != null) return cached;
    if (!directory.existsSync()) return null;
    return _resolvedRoot = await directory.resolveSymbolicLinks();
  }
}

ContentType _contentType(String path) =>
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

final RegExp _contentHash = RegExp(
  r'(?:^|[._-])[a-f0-9]{8,}(?:[._-]|$)',
  caseSensitive: false,
);
