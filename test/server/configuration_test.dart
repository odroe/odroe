import 'package:odroe/router.dart';
import 'package:odroe/server.dart';
import 'package:test/test.dart';

void main() {
  test('server configuration is an immutable snapshot', () {
    Future<ServerResponse> middleware(RequestContext _, Next next) => next();
    final definition = AppRoute<NoParams, NoSearch, NoData>(path: '/');
    final route = definition.server(
      middleware: <Middleware>[middleware],
      handlers: <HttpMethod, ServerRouteHandler<NoParams, NoSearch>>{
        HttpMethod.get: (_) => ServerResponse.text('ok'),
      },
    );
    final function = ServerFunction<NoServerInput, String>(
      handler: (_) => 'ok',
      middleware: <Middleware>[middleware],
    );
    final server = Server(
      routes: <RouteNode>[route],
      functions: <String, ServerFunctionBinding>{
        'read': ServerFunctionBinding(function),
      },
      middleware: <Middleware>[middleware],
    );

    expect(() => server.routes[0] = definition, throwsUnsupportedError);
    expect(server.functions.clear, throwsUnsupportedError);
    expect(() => server.middleware[0] = middleware, throwsUnsupportedError);
    expect(() => route.middleware[0] = middleware, throwsUnsupportedError);
    expect(route.handlers.clear, throwsUnsupportedError);
    expect(() => function.middleware[0] = middleware, throwsUnsupportedError);
  });

  test('method-not-allowed responses declare every supported method', () async {
    final route = AppRoute<NoParams, NoSearch, NoData>(path: '/').server(
      handlers: <HttpMethod, ServerRouteHandler<NoParams, NoSearch>>{
        HttpMethod.post: (_) => ServerResponse.text('created'),
      },
    );
    final server = Server(
      routes: <RouteNode>[route],
      renderer: (_) => ServerResponse.html('<main>ok</main>'),
      exposeErrors: true,
    );

    final response = await server.handle(
      ServerRequest.bytes(
        method: HttpMethod.delete,
        uri: Uri.parse('http://localhost/'),
      ),
    );

    final body = await response.readText();
    expect(response.status, 405, reason: body);
    expect(response.headers.value('allow'), 'GET, POST, HEAD');
  });
}
