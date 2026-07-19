// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'context.dart';
import 'http.dart';

typedef Next = Future<ServerResponse> Function();
typedef Middleware =
    FutureOr<ServerResponse> Function(RequestContext context, Next next);

Future<ServerResponse> runMiddleware(
  RequestContext context,
  List<Middleware> middleware,
  FutureOr<ServerResponse> Function() handler,
) {
  var index = -1;

  Future<ServerResponse> dispatch(int nextIndex) async {
    if (nextIndex <= index) {
      throw StateError('Middleware next() may only be called once.');
    }
    index = nextIndex;
    if (nextIndex == middleware.length) return handler();
    return middleware[nextIndex](context, () => dispatch(nextIndex + 1));
  }

  return dispatch(0);
}

/// Returns a rejection for cross-origin RPC, or null when it may proceed.
ServerResponse? rejectCrossOriginRpc(
  ServerRequest request, {
  bool allowWithoutOrigin = false,
}) {
  final fetchSite = request.headers.value('sec-fetch-site');
  if (fetchSite == 'cross-site' || fetchSite == 'same-site') {
    return ServerResponse.text(
      'Cross-origin server function request.',
      status: 403,
    );
  }
  if (fetchSite == 'same-origin') return null;

  final expectedOrigin = _origin(request.uri);
  final suppliedOrigin = request.headers.value('origin');
  if (suppliedOrigin != null) {
    return suppliedOrigin == expectedOrigin
        ? null
        : ServerResponse.text('Invalid Origin.', status: 403);
  }
  final referer = request.headers.value('referer');
  if (referer != null) {
    final parsed = Uri.tryParse(referer);
    return parsed != null && _origin(parsed) == expectedOrigin
        ? null
        : ServerResponse.text('Invalid Referer.', status: 403);
  }
  return allowWithoutOrigin
      ? null
      : ServerResponse.text('Origin metadata is required.', status: 403);
}

String _origin(Uri uri) {
  final defaultPort = uri.scheme == 'https' ? 443 : 80;
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}
