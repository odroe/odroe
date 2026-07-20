import 'dart:io';

import 'package:path/path.dart' as p;

/// Proxies Flutter development assets through the Odroe origin.
final class DevelopmentProxy {
  /// Creates a proxy that reads its Flutter origin from [originFile].
  DevelopmentProxy(this.originFile);

  /// The file written by the Flutter development launcher.
  final File originFile;
  final HttpClient _client = HttpClient();
  Uri? _origin;

  /// Closes the proxy's HTTP client.
  void close() => _client.close(force: true);

  /// Proxies [request] when it targets a Flutter development resource.
  Future<bool> serve(HttpRequest request) async {
    if (!_matches(request)) return false;
    final origin = await _resolveOrigin();
    if (origin == null) return false;
    final target = origin.replace(
      path: request.requestedUri.path,
      query: request.requestedUri.hasQuery ? request.requestedUri.query : null,
    );
    final outgoing = await _client.openUrl(request.method, target);
    request.headers.forEach((name, values) {
      if (_requestHopHeaders.contains(name.toLowerCase())) return;
      outgoing.headers.removeAll(name);
      for (final value in values) {
        outgoing.headers.add(name, value);
      }
    });
    if (request.method != 'GET' && request.method != 'HEAD') {
      await outgoing.addStream(request);
    }
    final response = await outgoing.close();
    request.response.statusCode = response.statusCode;
    response.headers.forEach((name, values) {
      if (_responseHopHeaders.contains(name.toLowerCase())) return;
      request.response.headers.removeAll(name);
      for (final value in values) {
        request.response.headers.add(name, value);
      }
    });
    if (request.method != 'HEAD') {
      await request.response.addStream(response);
    } else {
      await response.drain<void>();
    }
    return true;
  }

  bool _matches(HttpRequest request) {
    final path = request.requestedUri.path;
    final first = request.requestedUri.pathSegments.firstOrNull ?? '';
    if (request.requestedUri.pathSegments.any(
      (segment) => segment.startsWith(r'$'),
    )) {
      return true;
    }
    if (request.method != 'GET' && request.method != 'HEAD') return false;
    return _developmentFiles.contains(path) ||
        _developmentPrefixes.contains(first) ||
        first.startsWith(r'$') ||
        _developmentExtensions.contains(p.extension(path).toLowerCase());
  }

  Future<Uri?> _resolveOrigin() async {
    final cached = _origin;
    if (cached != null) return cached;
    for (var attempt = 0; attempt < 200; attempt++) {
      if (originFile.existsSync()) {
        final value = Uri.tryParse(originFile.readAsStringSync().trim());
        if (value != null && value.hasScheme && value.host.isNotEmpty) {
          return _origin = value;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }
}

const Set<String> _developmentFiles = <String>{
  '/flutter_bootstrap.js',
  '/flutter.js',
  '/favicon.ico',
  '/favicon.png',
  '/main.dart.js',
  '/manifest.json',
  '/version.json',
};
const Set<String> _developmentPrefixes = <String>{
  'assets',
  'canvaskit',
  'icons',
  'packages',
  'skwasm',
};
const Set<String> _developmentExtensions = <String>{
  '.dart.js',
  '.js',
  '.map',
  '.mjs',
  '.otf',
  '.ttf',
  '.wasm',
  '.woff',
  '.woff2',
};
const Set<String> _requestHopHeaders = <String>{
  'connection',
  'content-length',
  'host',
  'transfer-encoding',
  'upgrade',
};
const Set<String> _responseHopHeaders = <String>{
  'connection',
  'content-length',
  'transfer-encoding',
  'upgrade',
};
