// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Build-time behavior for static route generation.
final class StartPrerenderOptions {
  const StartPrerenderOptions({
    this.crawlLinks = true,
    this.failOnError = true,
    this.concurrency = 4,
    this.retries = 2,
    this.timeout = const Duration(seconds: 30),
  }) : assert(concurrency > 0),
       assert(retries >= 0);

  final bool crawlLinks;
  final bool failOnError;
  final int concurrency;
  final int retries;
  final Duration timeout;
}

/// One successfully generated route.
final class StartPrerenderedRoute {
  const StartPrerenderedRoute({
    required this.route,
    required this.file,
    required this.bytes,
    required this.elapsed,
  });

  final String route;
  final File file;
  final int bytes;
  final Duration elapsed;
}

/// One route that could not be generated.
final class StartPrerenderFailure {
  const StartPrerenderFailure({required this.route, required this.error});

  final String route;
  final Object error;
}

/// Result of a complete static generation pass.
final class StartPrerenderResult {
  const StartPrerenderResult({required this.routes, required this.failures});

  final List<StartPrerenderedRoute> routes;
  final List<StartPrerenderFailure> failures;
}

/// Fetches a built Start application and writes deployment-ready static HTML.
final class StartPrerenderer {
  StartPrerenderer({HttpClient? client}) : _client = client;

  final HttpClient? _client;

  Future<StartPrerenderResult> render({
    required Uri origin,
    required Iterable<String> routes,
    required Directory output,
    StartPrerenderOptions options = const StartPrerenderOptions(),
  }) async {
    if (!origin.hasScheme || origin.host.isEmpty) {
      throw ArgumentError.value(origin, 'origin', 'Origin must be absolute.');
    }
    if (options.concurrency <= 0) {
      throw ArgumentError.value(
        options.concurrency,
        'options.concurrency',
        'Concurrency must be positive.',
      );
    }
    if (options.retries < 0) {
      throw ArgumentError.value(
        options.retries,
        'options.retries',
        'Retries cannot be negative.',
      );
    }
    if (options.timeout <= Duration.zero) {
      throw ArgumentError.value(
        options.timeout,
        'options.timeout',
        'Timeout must be positive.',
      );
    }
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
    final generated = <StartPrerenderedRoute>[];
    final failures = <StartPrerenderFailure>[];
    var index = 0;

    Future<void> worker() async {
      while (true) {
        if (index >= queue.length) return;
        final currentIndex = index++;
        final route = queue[currentIndex];
        try {
          final page = await _renderRoute(
            client: client,
            origin: origin,
            route: route,
            output: root,
            options: options,
            enqueue: enqueue,
          );
          generated.add(page);
        } on Object catch (error) {
          failures.add(
            StartPrerenderFailure(route: route.toString(), error: error),
          );
        }
      }
    }

    try {
      await Future.wait<void>(
        List<Future<void>>.generate(options.concurrency, (_) => worker()),
      );
    } finally {
      if (_client == null) client.close(force: true);
    }
    generated.sort((left, right) => left.route.compareTo(right.route));
    failures.sort((left, right) => left.route.compareTo(right.route));
    if (options.failOnError && failures.isNotEmpty) {
      throw StartPrerenderException(failures);
    }
    return StartPrerenderResult(
      routes: List<StartPrerenderedRoute>.unmodifiable(generated),
      failures: List<StartPrerenderFailure>.unmodifiable(failures),
    );
  }

  Future<StartPrerenderedRoute> _renderRoute({
    required HttpClient client,
    required Uri origin,
    required Uri route,
    required Directory output,
    required StartPrerenderOptions options,
    required void Function(Uri) enqueue,
  }) async {
    final started = Stopwatch()..start();
    final target = origin.resolveUri(route);
    late HttpClientResponse response;
    for (var attempt = 0; attempt <= options.retries; attempt++) {
      try {
        final request = await client.getUrl(target).timeout(options.timeout);
        request
          ..followRedirects = false
          ..headers.set(HttpHeaders.acceptHeader, 'text/html')
          ..headers.set('x-odroe-prerender', 'true');
        response = await request.close().timeout(options.timeout);
        if (response.statusCode < 500 || attempt == options.retries) break;
        await response.drain<void>();
      } on Object catch (_) {
        if (attempt == options.retries) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
    }
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
      bytes = await response
          .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk))
          .timeout(options.timeout);
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

    if (options.crawlLinks) {
      final html = utf8.decode(bytes, allowMalformed: true);
      for (final link in _extractLinks(html)) {
        enqueue(route.resolveUri(link));
      }
    }
    started.stop();
    return StartPrerenderedRoute(
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
    if (route.query.isNotEmpty || route.pathSegments.contains('..')) {
      throw ArgumentError.value(route, 'route', 'Unsafe prerender route.');
    }
    final segments = route.pathSegments.where((value) => value.isNotEmpty);
    final relative = route.path.endsWith('.html')
        ? p.joinAll(segments)
        : p.join(p.joinAll(segments), 'index.html');
    final path = p.normalize(p.join(output.path, relative));
    if (!p.isWithin(output.path, path)) {
      throw ArgumentError.value(route, 'route', 'Route escapes output root.');
    }
    if (path.length > 1024 ||
        p.split(path).any((segment) => segment.length > 255)) {
      throw ArgumentError.value(route, 'route', 'Route is too long to write.');
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

/// A prerender pass containing one or more failed routes.
final class StartPrerenderException implements Exception {
  const StartPrerenderException(this.failures);

  final List<StartPrerenderFailure> failures;

  @override
  String toString() => failures
      .map((failure) => '${failure.route}: ${failure.error}')
      .join('\n');
}

const Set<int> _redirectStatuses = <int>{301, 302, 303, 307, 308};
final RegExp _href = RegExp(
  r'''<a\b[^>]*\bhref\s*=\s*(["'])(.*?)\1''',
  caseSensitive: false,
  dotAll: true,
);
