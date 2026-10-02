import 'dart:convert';

import 'package:odroe/query_rpc.dart';
import 'package:odroe/server_io.dart';

typedef Input = ({List<int> ids, Map<String, String> labels});
void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final server = await IoServer.bind((request) async {
    final envelope =
        jsonDecode(await utf8.decoder.bind(request.body).join()) as Map;
    return ServerResponse.json({
      'version': 1,
      'type': 'data',
      'data': envelope['data'],
    });
  }, port: 0);
  final transport = HttpTransport();
  final cache = QueryClient();
  try {
    final rpc = RpcClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/app/'),
      functionPath: 'rpc',
      transport: transport,
    );
    final ref = ServerFunctionRef<Input, Input>(
      id: 'echo',
      encodeInput: (input) => {'ids': input.ids, 'labels': input.labels},
      decodeOutput: (wire) {
        final map = wire as Map;
        return (
          ids: (map['ids'] as List).cast<int>(),
          labels: (map['labels'] as Map).cast<String, String>(),
        );
      },
    );
    final ids = [1];
    final labels = {'title': 'before'};
    final options = ref.read(
      rpc,
      (ids: ids, labels: labels),
      scope: ['tenant', 'alice'],
    );
    ids.add(2);
    labels['title'] = 'after';
    final value = await cache.fetchQuery(options);
    check(
      value.ids.length == 1 && value.labels['title'] == 'before',
      'input was not frozen',
    );
    check(
      cache.findAll(ref.reads(rpc, scope: ['tenant', 'alice'])).length == 1,
      'collection filter',
    );
    check(
      cache
              .findAll(
                ref.readAt(
                  rpc,
                  (ids: [1], labels: {'title': 'before'}),
                  scope: ['tenant', 'alice'],
                ),
              )
              .length ==
          1,
      'exact filter',
    );
    print(
      'Public entrypoint / typed record / real HTTP / snapshot / filters: passed',
    );
  } finally {
    cache.clear();
    transport.close();
    await IoServer.close(server, force: true);
  }
}
