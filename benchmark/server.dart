import 'dart:convert';

import 'package:odroe/document.dart';
import 'package:odroe/router.dart';
import 'package:odroe/rpc.dart';
import 'package:odroe/server.dart';

Future<void> main() async {
  final root =
      AppRoute<NoParams, NoSearch, NoData>(
        path: '/',
        metadata: const RouteMetadata(
          title: 'Odroe',
          description: 'Flutter full-stack framework.',
        ),
      ).document(
        (_) => const RouteDocument(
          language: 'en',
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
      );
  final app = Server(
    routes: <RouteNode>[root],
    functions: <String, ServerFunctionBinding>{
      'increment': ServerFunctionBinding(
        ServerFunction<int, int>(handler: (context) => context.data + 1),
      ),
    },
    renderer: const DocumentRenderer().call,
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

  final routing = Stopwatch()..start();
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
  routing.stop();
  _print('Route + JSON handoff', routing.elapsed, 2000);

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
