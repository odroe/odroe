import 'dart:io';

import 'package:path/path.dart' as p;

/// Serves one contained public directory for the IO adapter.
final class StaticFiles {
  /// Creates a server for files contained by [directory].
  StaticFiles(Directory directory, {required this.compress})
    : directory = directory.absolute;

  /// The public directory served by this instance.
  final Directory directory;

  /// Whether eligible responses may use gzip content encoding.
  final bool compress;
  String? _resolvedRoot;

  /// Serves [request] when it resolves to a public file.
  Future<bool> serve(HttpRequest request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      return false;
    }
    final segments = request.requestedUri.pathSegments;
    if (segments.any(_unsafeSegment)) return false;
    final relative = p.joinAll(segments);
    if (relative.isEmpty) return false;
    final asset = await _file(relative);
    if (asset == null) return false;
    final etag = _etag(asset.stat);
    final response = request.response;
    final compressible =
        compress &&
        asset.stat.size >= _minimumCompressionBytes &&
        _compressible(asset.file.path);
    final encoding = compressible
        ? _selectEncoding(request.headers)
        : _ContentEncoding.identity;
    if (compressible) {
      response.headers.set(HttpHeaders.varyHeader, 'Accept-Encoding');
    }
    if (encoding == _ContentEncoding.notAcceptable) {
      response
        ..statusCode = HttpStatus.notAcceptable
        ..contentLength = 0;
      return true;
    }
    final useGzip = encoding == _ContentEncoding.gzip;
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.etagHeader, etag)
      ..set(
        HttpHeaders.lastModifiedHeader,
        HttpDate.format(asset.stat.modified.toUtc()),
      )
      ..contentType = _contentType(asset.file.path);
    if (useGzip) {
      response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
    }
    if (_notModified(request.headers, etag, asset.stat.modified)) {
      response.statusCode = HttpStatus.notModified;
      return true;
    }

    response.statusCode = HttpStatus.ok;
    if (!useGzip) {
      response.contentLength = asset.stat.size;
    }
    if (request.method != 'HEAD') {
      final body = asset.file.openRead();
      await response.addStream(
        useGzip ? GZipCodec(level: 1).encoder.bind(body) : body,
      );
    }
    return true;
  }

  Future<({File file, FileStat stat})?> _file(String relative) async {
    final path = p.normalize(p.join(directory.path, relative));
    if (!p.isWithin(directory.path, path)) return null;
    final root = await _root();
    if (root == null) return null;
    try {
      final resolved = await File(path).resolveSymbolicLinks();
      if (!p.isWithin(root, resolved)) return null;
      final file = File(resolved);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      return (file: file, stat: stat);
    } on FileSystemException {
      return null;
    }
  }

  Future<String?> _root() async {
    final cached = _resolvedRoot;
    if (cached != null) return cached;
    try {
      return _resolvedRoot = await directory.resolveSymbolicLinks();
    } on FileSystemException {
      return null;
    }
  }
}

ContentType _contentType(String path) =>
    switch (p.extension(path).toLowerCase()) {
      '.css' => ContentType('text', 'css', charset: 'utf-8'),
      '.html' => ContentType.html,
      '.avif' => ContentType('image', 'avif'),
      '.gif' => ContentType('image', 'gif'),
      '.ico' => ContentType('image', 'x-icon'),
      '.jpeg' || '.jpg' => ContentType('image', 'jpeg'),
      '.js' || '.mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      '.json' || '.map' => ContentType.json,
      '.otf' => ContentType('font', 'otf'),
      '.png' => ContentType('image', 'png'),
      '.svg' => ContentType('image', 'svg+xml'),
      '.txt' => ContentType.text,
      '.ttf' => ContentType('font', 'ttf'),
      '.wasm' => ContentType('application', 'wasm'),
      '.webmanifest' => ContentType(
        'application',
        'manifest+json',
        charset: 'utf-8',
      ),
      '.webp' => ContentType('image', 'webp'),
      '.woff' => ContentType('font', 'woff'),
      '.woff2' => ContentType('font', 'woff2'),
      '.xml' => ContentType('application', 'xml', charset: 'utf-8'),
      _ => ContentType.binary,
    };

String _etag(FileStat stat) =>
    'W/"${stat.size.toRadixString(16)}-'
    '${stat.modified.millisecondsSinceEpoch.toRadixString(16)}"';

bool _notModified(HttpHeaders headers, String etag, DateTime modified) {
  final ifNoneMatch = headers[HttpHeaders.ifNoneMatchHeader];
  if (ifNoneMatch != null) {
    final expected = _weakTag(etag);
    return ifNoneMatch
        .expand((value) => value.split(','))
        .map((value) => value.trim())
        .any(
          (candidate) => candidate == '*' || _weakTag(candidate) == expected,
        );
  }
  final ifModifiedSince = headers.ifModifiedSince;
  if (ifModifiedSince == null) return false;
  final modifiedSeconds = DateTime.fromMillisecondsSinceEpoch(
    modified.toUtc().millisecondsSinceEpoch ~/ 1000 * 1000,
    isUtc: true,
  );
  return !modifiedSeconds.isAfter(ifModifiedSince.toUtc());
}

String _weakTag(String value) =>
    value.startsWith('W/') ? value.substring(2) : value;

_ContentEncoding _selectEncoding(HttpHeaders headers) {
  double? gzipQuality;
  double? identityQuality;
  double? wildcardQuality;
  for (final value in headers[HttpHeaders.acceptEncodingHeader] ?? const []) {
    for (final item in value.split(',')) {
      final parts = item.split(';');
      final encoding = parts.first.trim().toLowerCase();
      final quality = _quality(parts.skip(1));
      if (encoding == 'gzip') gzipQuality = quality;
      if (encoding == 'identity') identityQuality = quality;
      if (encoding == '*') wildcardQuality = quality;
    }
  }
  final identity = identityQuality ?? (wildcardQuality == 0 ? 0.0 : 1.0);
  final gzip = gzipQuality ?? wildcardQuality ?? 0.0;
  if (identity <= 0 && gzip <= 0) {
    return _ContentEncoding.notAcceptable;
  }
  if (gzip > 0 && gzip >= identity) return _ContentEncoding.gzip;
  return _ContentEncoding.identity;
}

double _quality(Iterable<String> parameters) {
  var quality = 1.0;
  for (final parameter in parameters) {
    final separator = parameter.indexOf('=');
    final name = (separator < 0 ? parameter : parameter.substring(0, separator))
        .trim()
        .toLowerCase();
    if (name != 'q') continue;
    if (separator < 0) return 0;
    final parsed = double.tryParse(parameter.substring(separator + 1).trim());
    quality = parsed != null && parsed >= 0 && parsed <= 1 ? parsed : 0;
  }
  return quality;
}

bool _compressible(String path) => switch (p.extension(path).toLowerCase()) {
  '.css' ||
  '.html' ||
  '.js' ||
  '.json' ||
  '.map' ||
  '.mjs' ||
  '.svg' ||
  '.txt' ||
  '.wasm' ||
  '.webmanifest' ||
  '.xml' => true,
  _ => false,
};

bool _unsafeSegment(String segment) =>
    segment == '.' ||
    segment == '..' ||
    segment.contains('\u0000') ||
    segment.contains('/') ||
    segment.contains(r'\') ||
    (Platform.isWindows && segment.contains(':'));

const _minimumCompressionBytes = 1024;

enum _ContentEncoding { identity, gzip, notAcceptable }
