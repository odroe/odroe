import 'dart:convert';

import 'package:odroe/route.dart';
import 'package:odroe/server.dart';

Future<void> main() async {
  final app = OdroeServer(
    routes: <RouteNode>[
      AppRoute<NoParams, NoSearch, NoData>(
        path: '/',
        document: (_) => const RouteDocument(
          language: 'en',
          title: 'Odroe',
          description: 'Flutter full-stack framework.',
          body: HtmlElement(
            'main',
            children: <HtmlNode>[
              HtmlElement('h1', children: <HtmlNode>[HtmlText('Odroe')]),
              HtmlElement(
                'p',
                children: <HtmlNode>[
                  HtmlText('Semantic HTML with a typed route contract.'),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
    functions: <String, ServerFunctionBinding>{
      'increment': ServerFunctionBinding(
        ServerFunction<int, int>(handler: (context) => context.data + 1),
      ),
    },
  );
  final client = RpcClient(
    baseUri: Uri.parse('http://localhost'),
    transport: _LocalTransport(app.handle),
  );
  const function = ServerFunctionRef<int, int>(id: 'increment');

  for (var index = 0; index < 200; index++) {
    await function.call(client, index);
  }
  final rpc = Stopwatch()..start();
  for (var index = 0; index < 2000; index++) {
    final result = await function.call(client, index);
    if (result != index + 1) throw StateError('Unexpected RPC value.');
  }
  rpc.stop();
  _print('In-memory typed RPC', rpc.elapsed, 2000);

  final route = Stopwatch()..start();
  for (var index = 0; index < 2000; index++) {
    final response = await app.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: Headers.single(<String, String>{'accept': 'application/json'}),
      ),
    );
    final payload = jsonDecode(await response.readText()) as Map;
    if (payload['location'] != '/') throw StateError('Unexpected route.');
  }
  route.stop();
  _print('Route + JSON handoff', route.elapsed, 2000);

  final document = Stopwatch()..start();
  for (var index = 0; index < 2000; index++) {
    final response = await app.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: Headers.single(<String, String>{'accept': 'text/html'}),
      ),
    );
    final html = await response.readText();
    if (!html.contains('<h1>Odroe</h1>')) {
      throw StateError('Unexpected document.');
    }
  }
  document.stop();
  _print('Route + semantic HTML', document.elapsed, 2000);
}

final class _LocalTransport implements RpcTransport {
  const _LocalTransport(this._handler);

  final Future<ServerResponse> Function(ServerRequest request) _handler;

  @override
  Future<ServerResponse> send(ServerRequest request) => _handler(request);
}

void _print(String name, Duration elapsed, int iterations) {
  final microseconds = elapsed.inMicroseconds / iterations;
  print('$name: ${microseconds.toStringAsFixed(2)} us/op');
}
