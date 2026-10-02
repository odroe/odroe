import 'dart:convert';
import 'dart:js_interop';

import 'package:odroe/query_rpc.dart';
import 'package:web/web.dart' as web;

const ref = ServerFunctionRef<int, Map<String, Object?>>(
  id: 'echo',
  decodeOutput: decode,
);
Map<String, Object?> decode(Object? wire) => (wire as Map).cast();
void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final location = Uri.base;
  final cache = QueryClient();
  final transport = HttpTransport();
  final moduleTransport = HttpTransport();
  final module = RpcModule.http(transport: moduleTransport);
  final base = web.document.querySelector('base') as web.HTMLBaseElement;
  final initialBase = base.href;
  RpcClient client(Uri uri, {String path = 'rpc', String account = 'alice'}) =>
      RpcClient(
        baseUri: uri,
        functionPath: path,
        transport: transport,
        headersProvider: () => Headers.single({'x-account': account}),
      );
  var checks = 0;
  Future<void> verify(
    RpcClient rpc,
    String expected, {
    String account = 'alice',
  }) async {
    final options = ref.read(rpc, 7, scope: ['tenant', account]);
    final direct = await ref(rpc, 7);
    // Control: hand the original unresolved RPC URI straight to Fetch, as the
    // pre-bridge client did. This proves document-base behavior independently
    // of the new shared resolver.
    final control = await transport.send(
      ServerRequest.bytes(
        method: HttpMethod.post,
        uri: rpc.baseUri.resolve('${rpc.functionPath}/echo'),
        body: utf8.encode('{"data":7}'),
      ),
    );
    final controlFrame =
        jsonDecode(await utf8.decoder.bind(control.body).join()) as Map;
    check(
      (controlFrame['data'] as Map)['path'] == expected,
      'Fetch control disagrees with resolved endpoint',
    );
    final result = await cache.fetchQuery(options);
    check(result['path'] == expected, 'wire path: $result vs $expected');
    check(direct['path'] == expected, 'direct call disagrees with bridge');
    check(
      options.key.parts.first == location.resolve(expected).toString(),
      'key differs from destination',
    );
    check(
      cache.findAll(ref.readAt(rpc, 7, scope: ['tenant', account])).length == 1,
      'exact filter',
    );
    checks++;
  }

  try {
    // Default module uses Uri.base; direct RpcClient permits browser-relative URLs.
    await verify(module.client, '/__odroe/functions/echo');
    await verify(client(Uri()), '/document/a/rpc/echo');
    await verify(client(Uri.parse('api/')), '/document/a/api/rpc/echo');
    await verify(client(Uri.parse('/api/')), '/api/rpc/echo');
    await verify(
      client(Uri.parse('//${location.authority}/api/')),
      '/api/rpc/echo',
    );
    await verify(
      client(Uri(), path: 'functions'),
      '/document/a/functions/echo',
    );
    final rpc = client(Uri());
    final frozen = ref.read(rpc, 9, scope: ['tenant', 'alice']);
    base.href = '/document/b/';
    final changed = ref.read(rpc, 9, scope: ['tenant', 'alice']);
    check(frozen.key != changed.key, 'different document bases share a key');
    check(
      (await cache.fetchQuery(frozen))['path'] == '/document/a/rpc/echo',
      'prepared destination moved',
    );
    await verify(rpc, '/document/b/rpc/echo');
    check(
      cache
          .findAll(ref.reads(rpc, scope: ['tenant', 'alice']))
          .every(
            (q) =>
                q.key.parts.first ==
                location.resolve('/document/b/rpc/echo').toString(),
          ),
      'collection crossed document bases',
    );
    web.window.history.pushState(null, '', '/navigation/page.html');
    check(Uri.base != location, 'page location did not change');
    check(
      ref.read(rpc, 9, scope: ['tenant', 'alice']).key == changed.key,
      'location overrides explicit document base',
    );
    base.remove();
    await verify(rpc, '/navigation/rpc/echo');
    final bob = client(Uri(), account: 'bob');
    await verify(bob, '/navigation/rpc/echo', account: 'bob');
    final aliceOptions = ref.read(rpc, 7, scope: ['tenant', 'alice']);
    final bobOptions = ref.read(bob, 7, scope: ['tenant', 'bob']);
    check(aliceOptions.key != bobOptions.key, 'accounts share a cache key');
    check(
      (await cache.fetchQuery(aliceOptions))['account'] == 'alice',
      'Alice cache overwritten',
    );
    check(
      (await cache.fetchQuery(bobOptions))['account'] == 'bob',
      'Bob received Alice cache',
    );
    await report(location, {
      'passed': true,
      'endpointCases': checks,
      'documentBaseDiffersFromLocation': initialBase != location.toString(),
      'preparedDestinationFrozen': true,
      'accountIsolation': true,
    });
  } catch (error, stack) {
    await report(location, {
      'passed': false,
      'error': '$error',
      'stack': '$stack',
    });
  } finally {
    cache.clear();
    transport.close();
    moduleTransport.close();
  }
}

Future<void> report(Uri location, Map<String, Object?> result) async {
  await web.window
      .fetch(
        location.resolve('/report').toString().toJS,
        web.RequestInit(method: 'POST', body: jsonEncode(result).toJS),
      )
      .toDart;
}
