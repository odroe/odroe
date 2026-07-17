import 'dart:async';

import 'context.dart';
import 'request.dart';

typedef StartNext = Future<StartResponse> Function();
typedef StartMiddleware =
    FutureOr<StartResponse> Function(
      StartRequestContext context,
      StartNext next,
    );

Future<StartResponse> runStartMiddleware(
  StartRequestContext context,
  Iterable<StartMiddleware> middleware,
  FutureOr<StartResponse> Function() handler,
) {
  final chain = List<StartMiddleware>.unmodifiable(middleware);
  var index = -1;

  Future<StartResponse> dispatch(int nextIndex) async {
    if (nextIndex <= index) {
      throw StateError('Start middleware next() may only be called once.');
    }
    index = nextIndex;
    if (nextIndex == chain.length) return handler();
    return chain[nextIndex](context, () => dispatch(nextIndex + 1));
  }

  return dispatch(0);
}

/// Protects same-origin server-function requests using browser metadata.
final class StartCsrfMiddleware {
  const StartCsrfMiddleware({
    this.origin,
    this.allowRequestsWithoutOrigin = false,
  });

  final Uri? origin;
  final bool allowRequestsWithoutOrigin;

  Future<StartResponse> call(
    StartRequestContext context,
    StartNext next,
  ) async {
    if (context.type != StartHandlerType.serverFunction) return next();
    final request = context.request;
    final fetchSite = request.headers.value('sec-fetch-site');
    if (fetchSite == 'cross-site' || fetchSite == 'same-site') {
      return StartResponse.text(
        'Cross-origin server function request.',
        status: 403,
      );
    }
    if (fetchSite == 'same-origin') return next();

    final expected = origin ?? request.uri;
    final expectedOrigin = _origin(expected);
    final suppliedOrigin = request.headers.value('origin');
    if (suppliedOrigin != null) {
      return suppliedOrigin == expectedOrigin
          ? next()
          : StartResponse.text('Invalid Origin.', status: 403);
    }
    final referer = request.headers.value('referer');
    if (referer != null) {
      final parsed = Uri.tryParse(referer);
      return parsed != null && _origin(parsed) == expectedOrigin
          ? next()
          : StartResponse.text('Invalid Referer.', status: 403);
    }
    return allowRequestsWithoutOrigin
        ? next()
        : StartResponse.text('Origin metadata is required.', status: 403);
  }
}

String _origin(Uri uri) {
  final defaultPort = uri.scheme == 'https' ? 443 : 80;
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}
