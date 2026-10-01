import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// One successfully generated route.
final class PrerenderedRoute {
  /// Describes a generated route and its output file.
  const PrerenderedRoute({
    required this.route,
    required this.file,
    required this.bytes,
    required this.elapsed,
  });

  /// The route URL that was rendered.
  final String route;

  /// The generated HTML file.
  final File file;

  /// The generated file size.
  final int bytes;

  /// The time spent fetching and writing the route.
  final Duration elapsed;
}

/// Fetches a built Odroe server and writes deployment-ready static HTML.
final class Prerenderer {
  /// Creates a prerenderer, optionally reusing [client].
  Prerenderer({HttpClient? client}) : _client = client;

  /// Default number of concurrent route requests.
  static const int defaultConcurrency = 4;

  /// Default maximum number of explicit and discovered routes.
  static const int defaultMaxRoutes = 1000;

  /// Default maximum HTML response size for one route.
  static const int defaultMaxResponseBytes = 1024 * 1024;

  final HttpClient? _client;

  /// Renders [routes] from [origin] into [output].
  ///
  /// Explicit routes must be same-origin absolute paths without queries.
  /// Link crawling is opt-in. [maxRoutes] and [maxResponseBytes] bound work
  /// regardless of whether routes are explicit or discovered.
  Future<List<PrerenderedRoute>> render({
    required Uri origin,
    required Iterable<String> routes,
    required Directory output,
    int concurrency = defaultConcurrency,
    bool crawlLinks = false,
    int maxRoutes = defaultMaxRoutes,
    int maxResponseBytes = defaultMaxResponseBytes,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (concurrency < 1) {
      throw ArgumentError.value(
        concurrency,
        'concurrency',
        'Must be at least 1.',
      );
    }
    if (maxRoutes < 1) {
      throw ArgumentError.value(maxRoutes, 'maxRoutes', 'Must be at least 1.');
    }
    if (maxResponseBytes < 1) {
      throw ArgumentError.value(
        maxResponseBytes,
        'maxResponseBytes',
        'Must be at least 1.',
      );
    }
    final client = _client ?? HttpClient();
    final root = output.absolute;
    final queue = <Uri>[];
    final seen = <String>{};
    final outputRoutes = <String, String>{};
    void enqueue(Uri uri, {bool explicit = false}) {
      if (explicit &&
          (!uri.hasAbsolutePath ||
              uri.hasScheme ||
              uri.hasAuthority ||
              uri.hasQuery ||
              uri.hasFragment ||
              uri.pathSegments.any(
                (segment) => segment == '.' || segment == '..',
              ))) {
        throw ArgumentError.value(
          uri,
          'routes',
          'Must be an absolute local path without query or fragment.',
        );
      }
      final normalized = _localRoute(origin, uri);
      if (normalized == null) {
        if (explicit) {
          throw ArgumentError.value(
            uri,
            'routes',
            'Must be an absolute local path without query or fragment.',
          );
        }
        return;
      }
      final route = normalized.toString();
      if (seen.contains(route)) return;
      if (seen.length >= maxRoutes) {
        throw StateError(
          'Prerender route limit of $maxRoutes exceeded while adding "$route".',
        );
      }
      seen.add(route);
      final file = _outputFile(root, normalized);
      final relative = p.relative(file.path, from: root.path);
      final outputKey = p.normalize(relative).toLowerCase();
      final existing = outputRoutes[outputKey];
      if (existing != null) {
        throw StateError(
          'Prerender routes "$existing" and "$route" both write "$relative".',
        );
      }
      outputRoutes[outputKey] = route;
      queue.add(normalized);
    }

    final generated = <PrerenderedRoute>[];
    var index = 0;

    try {
      for (final route in routes) {
        enqueue(Uri.parse(route), explicit: true);
      }
      output.createSync(recursive: true);
      while (index < queue.length) {
        final end = queue.length;
        Future<void> worker() async {
          while (index < end) {
            final route = queue[index++];
            final page = await _renderRoute(
              client: client,
              origin: origin,
              route: route,
              output: root,
              crawlLinks: crawlLinks,
              maxResponseBytes: maxResponseBytes,
              timeout: timeout,
              enqueue: enqueue,
            );
            generated.add(page);
          }
        }

        final remaining = end - index;
        final workerCount = concurrency < remaining ? concurrency : remaining;
        final workers = List<Future<void>>.generate(
          workerCount,
          (_) => worker(),
        );
        if (workers.isEmpty) break;
        await Future.wait<void>(workers);
      }
    } finally {
      if (_client == null) client.close(force: true);
    }
    generated.sort((left, right) => left.route.compareTo(right.route));
    return generated;
  }

  Future<PrerenderedRoute> _renderRoute({
    required HttpClient client,
    required Uri origin,
    required Uri route,
    required Directory output,
    required bool crawlLinks,
    required int maxResponseBytes,
    required Duration timeout,
    required void Function(Uri) enqueue,
  }) async {
    final started = Stopwatch()..start();
    final target = origin.resolveUri(route);
    final request = await client.getUrl(target).timeout(timeout);
    request
      ..followRedirects = false
      ..headers.set(HttpHeaders.acceptHeader, 'text/html')
      ..headers.set('x-odroe-prerender', 'true');
    final response = await request.close().timeout(
      timeout,
      onTimeout: () {
        final error = TimeoutException(
          'Prerender response headers timed out.',
          timeout,
        );
        request.abort(error);
        throw error;
      },
    );
    late final List<int> bytes;
    final status = response.statusCode;
    final generatedRedirect = _redirectStatuses.contains(status);
    if (generatedRedirect) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.listen(null).cancel();
      if (location == null) {
        throw HttpException('Redirect has no location.', uri: target);
      }
      final redirected = _localRoute(origin, target.resolve(location));
      if (redirected == null) {
        throw HttpException(
          'Cannot prerender an external redirect.',
          uri: target,
        );
      }
      enqueue(redirected);
      bytes = utf8.encode(
        '<!doctype html><html><head><meta charset="utf-8">'
        '<meta http-equiv="refresh" content="0;url=${_attribute(redirected.toString())}">'
        '<link rel="canonical" href="${_attribute(redirected.toString())}">'
        '</head></html>',
      );
    } else {
      final contentType = response.headers.contentType?.mimeType;
      String? rejection;
      if (status != HttpStatus.ok) {
        rejection = 'Route returned $status ${response.reasonPhrase}.';
      } else if (contentType != ContentType.html.mimeType) {
        rejection =
            'Expected text/html but received '
            '${contentType ?? 'no content type'}.';
      } else if (response.contentLength > maxResponseBytes) {
        rejection = 'Route exceeds the $maxResponseBytes byte prerender limit.';
      }
      if (rejection != null) {
        await response.listen(null).cancel();
        throw HttpException(rejection, uri: target);
      }
      bytes = await _readBody(
        response,
        target: target,
        maxBytes: maxResponseBytes,
        timeout: timeout,
      );
    }
    if (bytes.length > maxResponseBytes) {
      throw HttpException(
        'Route exceeds the $maxResponseBytes byte prerender limit.',
        uri: target,
      );
    }
    final file = _outputFile(output, route);
    file.parent.createSync(recursive: true);
    await file.writeAsBytes(bytes, flush: true);

    if (crawlLinks) {
      final html = utf8.decode(bytes, allowMalformed: true);
      for (final link in _extractLinks(html)) {
        final discovered = route.resolveUri(link);
        final extension = p.extension(discovered.path).toLowerCase();
        if (extension.isEmpty || extension == '.html') enqueue(discovered);
      }
    }
    started.stop();
    return PrerenderedRoute(
      route: route.toString(),
      file: file,
      bytes: bytes.length,
      elapsed: started.elapsed,
    );
  }

  static Uri? _localRoute(Uri origin, Uri value) {
    final absolute = value.hasScheme ? value : origin.resolveUri(value);
    if (absolute.scheme != origin.scheme ||
        absolute.host != origin.host ||
        absolute.port != origin.port ||
        absolute.userInfo.isNotEmpty ||
        absolute.query.isNotEmpty) {
      return null;
    }
    var path = absolute.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final route = Uri(path: path);
    if (!route.hasAbsolutePath ||
        route.pathSegments.any((segment) => segment == '..')) {
      return null;
    }
    return route;
  }

  static File _outputFile(Directory output, Uri route) {
    final segments = route.pathSegments.where((value) => value.isNotEmpty);
    final relative = route.path.endsWith('.html')
        ? p.joinAll(segments)
        : p.join(p.joinAll(segments), 'index.html');
    final path = p.normalize(p.join(output.path, relative));
    if (!p.isWithin(output.path, path)) {
      throw ArgumentError.value(route, 'route', 'Route escapes output root.');
    }
    return File(path);
  }

  static Iterable<Uri> _extractLinks(String html) sync* {
    for (final match in _href.allMatches(html)) {
      final source = match.group(2);
      if (source == null || source.isEmpty || source.startsWith('#')) continue;
      final decoded = source
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>');
      final uri = Uri.tryParse(decoded);
      if (uri != null) yield uri;
    }
  }

  static String _attribute(String value) =>
      const HtmlEscape(HtmlEscapeMode.attribute).convert(value);
}

Future<List<int>> _readBody(
  HttpClientResponse response, {
  required Uri target,
  required int maxBytes,
  required Duration timeout,
}) async {
  final body = BytesBuilder(copy: false);
  final chunks = StreamIterator<List<int>>(response);
  final elapsed = Stopwatch()..start();
  try {
    while (true) {
      final remaining = timeout - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Prerender response timed out.', timeout);
      }
      final available = await chunks.moveNext().timeout(
        remaining,
        onTimeout: () {
          throw TimeoutException('Prerender response timed out.', timeout);
        },
      );
      if (!available) return body.takeBytes();
      final chunk = chunks.current;
      if (body.length + chunk.length > maxBytes) {
        throw HttpException(
          'Route exceeds the $maxBytes byte prerender limit.',
          uri: target,
        );
      }
      body.add(chunk);
    }
  } finally {
    await chunks.cancel();
  }
}

const Set<int> _redirectStatuses = <int>{301, 302, 303, 307, 308};
final RegExp _href = RegExp(
  r'''<a\b[^>]*\bhref\s*=\s*(["'])(.*?)\1''',
  caseSensitive: false,
  dotAll: true,
);
