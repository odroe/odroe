import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/odroe.dart';
import 'package:odroe/rpc.dart';
import 'package:test/test.dart';

void main() {
  test('default HTTP transport resolves bearer headers per request', () async {
    final authorizations = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      authorizations.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'version': 1,
          'type': 'data',
          'data': authorizations.length,
        }),
      );
      await request.response.close();
    });

    var token = 'first';
    var providerCalls = 0;
    final context = await AppContext.create(<Module>[
      RpcModule.http(
        baseUri: Uri(
          scheme: 'http',
          host: server.address.address,
          port: server.port,
        ),
        headersProvider: () async {
          providerCalls++;
          await Future<void>.delayed(Duration.zero);
          return Headers.single(<String, String>{
            'authorization': 'Bearer $token',
          });
        },
      ),
    ]);
    addTearDown(context.dispose);
    final client = context.read(rpcClientKey);
    const function = ServerFunctionRef<NoServerInput, int>(id: 'session.read');

    expect(await function(client, const NoServerInput()), 1);
    token = 'second';
    expect(await function(client, const NoServerInput()), 2);

    expect(providerCalls, 2);
    expect(authorizations, <String?>['Bearer first', 'Bearer second']);
  });
}
