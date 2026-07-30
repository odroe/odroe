import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:odroe/server_fetch.dart';

void main() {
  final server = Server(
    routes: const [],
    middleware: <Middleware>[
      (context, _) => _handle(context.request, context.invocation),
    ],
  );
  exportFetchHandler(server.invocationHandler);
}

Future<ServerResponse> _handle(
  ServerRequest request,
  ServerInvocation invocation,
) async {
  final env = _Environment(invocation.requireBindings<FetchBindings>().raw);
  switch (request.uri.path) {
    case '/echo':
      final body = await request.readBytes();
      final headers = Headers()
        ..set('x-method', request.method.wire)
        ..set('x-query', request.uri.query)
        ..set('x-request-header', request.headers.value('x-request') ?? '')
        ..set('x-binding', env.marker)
        ..append('x-multi', 'one')
        ..append('x-multi', 'two')
        ..append('set-cookie', 'a=1')
        ..append('set-cookie', 'b=2');
      return ServerResponse(
        status: 201,
        reason: 'Created by Odroe',
        headers: headers,
        body: Stream<List<int>>.value(body),
      );
    case '/request-cancel':
      return ServerResponse.bytes(await request.body.first);
    case '/abort':
      await request.cancelled!;
      return ServerResponse.text('cancelled', status: 499);
    case '/stream':
      Stream<List<int>> body() async* {
        try {
          for (var index = 0; index < 5; index++) {
            env.produced = index + 1;
            yield utf8.encode('$index');
          }
        } finally {
          env.responseCancelled = true;
        }
      }

      return ServerResponse(body: body());
    case '/head':
      return ServerResponse(body: _discardedBody(env));
    case '/wait':
      invocation.waitUntil(
        Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      return ServerResponse.text('scheduled');
    case '/invalid-response':
      return ServerResponse(status: 700, body: _discardedBody(env));
    default:
      if (request.uri.path.startsWith('/status/')) {
        final status = int.parse(request.uri.path.split('/').last);
        return ServerResponse(status: status, body: _discardedBody(env));
      }
      return ServerResponse.text('not found', status: 404);
  }
}

Stream<List<int>> _discardedBody(_Environment env) async* {
  try {
    yield <int>[1, 2, 3];
  } finally {
    env.responseCancelled = true;
  }
}

extension type _Environment(JSObject _) implements JSObject {
  external String get marker;

  external int get produced;
  external set produced(int value);

  external bool get responseCancelled;
  external set responseCancelled(bool value);
}
