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

  final HttpClient? _client;

  /// Renders [routes] from [origin] into [output].
  Future<List<PrerenderedRoute>> render({
    required Uri origin,
    required Iterable<String> routes,
    required Directory output,
    int concurrency = 4,
    bool crawlLinks = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = _client ?? HttpClient();
    output.createSync(recursive: true);
    final root = output.absolute;
    final queue = <Uri>[];
    final seen = <String>{};
    void enqueue(Uri uri) {
      final normalized = _localRoute(origin, uri);
      if (normalized == null || !seen.add(normalized.toString())) return;
      queue.add(normalized);
    }

    for (final route in routes) {
      enqueue(Uri.parse(route));
    }
    final generated = <PrerenderedRoute>[];
    var index = 0;

    try {
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
              timeout: timeout,
              enqueue: enqueue,
            );
            generated.add(page);
          }
        }

        final workers = List<Future<void>>.generate(
          concurrency,
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
    final response = await request.close().timeout(timeout);
    late final List<int> bytes;
    final status = response.statusCode;
    final generatedRedirect = _redirectStatuses.contains(status);
    if (generatedRedirect) {
      await response.drain<void>();
      final location = response.headers.value(HttpHeaders.locationHeader);
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
      final body = await response
          .fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (builder, chunk) => builder..add(chunk),
          )
          .timeout(timeout);
      bytes = body.takeBytes();
      if (status != HttpStatus.ok) {
        throw HttpException(
          'Route returned $status ${response.reasonPhrase}.',
          uri: target,
        );
      }
    }

    final contentType = response.headers.contentType?.mimeType;
    if (!generatedRedirect && contentType != ContentType.html.mimeType) {
      throw HttpException(
        'Expected text/html but received ${contentType ?? 'no content type'}.',
        uri: target,
      );
    }
    final file = _outputFile(output, route);
    file.parent.createSync(recursive: true);
    await file.writeAsBytes(bytes, flush: true);

    if (crawlLinks) {
      final html = utf8.decode(bytes, allowMalformed: true);
      for (final link in _extractLinks(html)) {
        enqueue(route.resolveUri(link));
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
    final path = absolute.path.length > 1 && absolute.path.endsWith('/')
        ? absolute.path.substring(0, absolute.path.length - 1)
        : absolute.path;
    final route = Uri(path: path);
    if (!route.hasAbsolutePath ||
        route.pathSegments.any((segment) => segment == '..')) {
      return null;
    }
    final extension = p.extension(route.path).toLowerCase();
    if (extension.isNotEmpty && extension != '.html') return null;
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

const Set<int> _redirectStatuses = <int>{301, 302, 303, 307, 308};
final RegExp _href = RegExp(
  r'''<a\b[^>]*\bhref\s*=\s*(["'])(.*?)\1''',
  caseSensitive: false,
  dotAll: true,
);
