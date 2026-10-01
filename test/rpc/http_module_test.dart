import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:odroe/odroe.dart';
import 'package:odroe/rpc.dart';
import 'package:test/test.dart';

void main() {
  test('invalid HTTP base URIs fail before creating or using a client', () {
    var creations = 0;
    final client = _RecordingClient();
    http.runWithClient(
      () {
        for (final uri in <Uri>[
          Uri.parse('/api'),
          Uri.parse('//api.example.com'),
          Uri.parse('http:///rpc'),
          Uri.parse('file:///app'),
          Uri.parse('ftp://api.example.com'),
          Uri.parse('https://user@api.example.com'),
          Uri.parse('https://user:password@api.example.com'),
        ]) {
          expect(
            () => RpcModule.http(baseUri: uri),
            throwsA(
              isA<ArgumentError>()
                  .having((error) => error.name, 'name', 'baseUri')
                  .having((error) => error.invalidValue, 'invalidValue', uri),
            ),
            reason: uri.toString(),
          );
        }
      },
      () {
        creations++;
        return client;
      },
    );
    expect(creations, 0);
    expect(client.requests, isEmpty);
    expect(client.closes, 0);
  });

  test('invalid base URI leaves a caller-owned transport untouched', () {
    final client = _RecordingClient();
    final transport = HttpTransport(client: client);
    expect(
      () => RpcModule.http(baseUri: Uri.parse('/api'), transport: transport),
      throwsArgumentError,
    );
    expect(client.requests, isEmpty);
    expect(client.closes, 0);
  });

  test(
    'omitted URI uses browser origin or fails before native client creation',
    () async {
      var creations = 0;
      final client = _RecordingClient();
      await http.runWithClient(
        () async {
          if (Uri.base.scheme == 'http' || Uri.base.scheme == 'https') {
            final module = RpcModule.http();
            expect(module.client.baseUri, Uri.base);
            expect(creations, 1);
            final context = await AppContext.create(<Module>[module]);
            expect(await _read.call(context.read(rpcClientKey), 7), 'ok');
            expect(
              client.requests.single.url,
              Uri.base.resolve('/__odroe/functions/read'),
            );
            await context.dispose();
            expect(client.closes, 1);
          } else {
            expect(() => RpcModule.http(), throwsArgumentError);
            expect(creations, 0);
            expect(client.requests, isEmpty);
            expect(client.closes, 0);
          }
        },
        () {
          creations++;
          return client;
        },
      );
    },
  );

  test(
    'HTTP(S) base URIs preserve endpoint paths and caller ownership',
    () async {
      for (final uri in <Uri>[
        Uri.parse('http://localhost:8080'),
        Uri.parse('https://api.example.com/app/?tenant=one#tab'),
        Uri.parse('http://[::1]:8080'),
      ]) {
        final client = _RecordingClient();
        final transport = HttpTransport(client: client);
        final module = RpcModule.http(baseUri: uri, transport: transport);
        final context = await AppContext.create(<Module>[module]);
        expect(module.client.baseUri, uri);
        expect(await _read.call(context.read(rpcClientKey), 7), 'ok');
        final request = client.requests.single;
        expect(request.url, uri.resolve('/__odroe/functions/read'));
        expect(request.method, 'POST');
        expect(request.headers['x-odroe-server-function'], 'true');
        expect(jsonDecode(utf8.decode(client.bodies.single)), <String, Object?>{
          'data': 7,
        });
        await context.dispose();
        expect(client.closes, 0);
      }
      final client = _RecordingClient();
      final uri = Uri.parse('https://api.example.com/app/?tenant=one#tab');
      final module = RpcModule.http(
        baseUri: uri,
        transport: HttpTransport(client: client),
        functionPath: 'functions',
      );
      expect(await _read.call(module.client, 7), 'ok');
      expect(
        client.requests.single.url,
        Uri.parse('https://api.example.com/app/functions/read'),
      );
    },
  );

  test(
    'module-owned client closes through the application lifecycle',
    () async {
      final client = _RecordingClient();
      await http.runWithClient(() async {
        final module = RpcModule.http(
          baseUri: Uri.parse('https://api.example.com'),
        );
        final context = await AppContext.create(<Module>[module]);
        expect(await _read.call(context.read(rpcClientKey), 7), 'ok');
        await context.dispose();
        await context.dispose();
        expect(client.closes, 1);
      }, () => client);
    },
  );

  test('standalone RPC keeps custom non-HTTP transports available', () async {
    final transport = _LocalTransport();
    final client = RpcClient(
      baseUri: Uri.parse('memory://app'),
      transport: transport,
    );
    final context = await AppContext.create(<Module>[RpcModule(client)]);
    expect(await _read.call(context.read(rpcClientKey), 7), 'local');
    expect(transport.requests.single.uri.scheme, 'memory');
    await context.dispose();
  });
}

const _read = ServerFunctionRef<int, String>(id: 'read');

final class _RecordingClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final bodies = <List<int>>[];
  var closes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    bodies.add(await request.finalize().toBytes());
    return http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode('{"version":1,"type":"data","data":"ok"}'),
      ),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }

  @override
  void close() => closes++;
}

final class _LocalTransport implements RpcTransport {
  final requests = <ServerRequest>[];

  @override
  Future<ServerResponse> send(ServerRequest request) async {
    requests.add(request);
    return ServerResponse.json(<String, Object?>{
      'version': 1,
      'type': 'data',
      'data': 'local',
    });
  }
}
