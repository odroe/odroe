import 'dart:convert';
import 'dart:io';

import 'package:odroe/server_io.dart';
import 'package:test/test.dart';

void main() {
  test('public origin is canonical and validated before server startup', () {
    for (final source in <String>[
      'https://example.com',
      'https://example.com/',
      'https://example.com:443/',
      'http://example.com:8080/',
      'https://[::1]:8443/',
    ]) {
      final origin = Uri.parse(source);
      expect(
        Server(routes: const [], publicOrigin: origin).publicOrigin.toString(),
        origin.origin,
      );
    }
    for (final source in <String>[
      '',
      '/local',
      '//example.com',
      'https:example.com',
      'ftp://example.com',
      'https://user:secret@example.com',
      'https://example.com/api',
      'https://example.com/?',
      'https://example.com/#',
      'https://example.com:0',
      'https://example.com:65536',
    ]) {
      expect(
        () => Server(routes: const [], publicOrigin: Uri.parse(source)),
        throwsArgumentError,
        reason: source,
      );
    }
  });

  test(
    'fixed public origin works on the actual plaintext IO upstream',
    () async {
      var calls = 0;
      final app = Server(
        routes: const [],
        publicOrigin: Uri.parse('https://public.example:8443'),
        functions: <String, ServerFunctionBinding>{
          'write': ServerFunctionBinding(
            ServerFunction<NoServerInput, int>(handler: (_) => ++calls),
          ),
        },
      );
      final server = await IoServer.bind(app.handle, port: 0);
      addTearDown(() => IoServer.close(server, force: true));
      addTearDown(app.close);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final endpoint = Uri.parse(
        'http://127.0.0.1:${server.port}/__odroe/functions/write',
      );
      Future<int> send(Map<String, String> headers) async {
        final request = await client.postUrl(endpoint);
        request.headers
          ..contentType = ContentType.json
          ..set('x-odroe-server-function', 'true');
        headers.forEach(request.headers.set);
        request.write('{"data":null}');
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode == 200) {
          expect(jsonDecode(body), containsPair('type', 'data'));
        }
        return response.statusCode;
      }

      expect(await send({'origin': 'https://public.example:8443'}), 200);
      expect(
        await send({
          'referer': 'https://public.example:8443/products?view=all',
        }),
        200,
      );
      expect(
        await send({
          'origin': 'https://public.example:8443',
          'x-forwarded-proto': 'http',
          'x-forwarded-host': 'spoofed.example',
        }),
        200,
      );
      for (final headers in <Map<String, String>>[
        {'origin': 'http://public.example:8443'},
        {'origin': 'https://other.example:8443'},
        {'origin': 'https://public.example'},
        {'origin': endpoint.origin},
        {
          'origin': 'https://spoofed.example',
          'x-forwarded-proto': 'https',
          'x-forwarded-host': 'spoofed.example',
        },
        {
          'origin': 'https://other.example:8443',
          'sec-fetch-site': 'same-origin',
        },
        {
          'origin': 'https://public.example:8443',
          'sec-fetch-site': 'same-site',
        },
        {
          'origin': 'https://public.example:8443',
          'sec-fetch-site': 'cross-site',
        },
        {
          'origin': 'https://other.example:8443',
          'referer': 'https://public.example:8443/',
        },
        {'referer': 'http://public.example:8443/'},
        {'referer': 'https://other.example:8443/'},
        {'referer': 'https://public.example:9443/'},
        {},
        {'sec-fetch-site': 'same-origin'},
      ]) {
        expect(await send(headers), 403, reason: headers.toString());
      }
      expect(calls, 3);
    },
  );

  test('fixed IPv6 origin accepts the matching Referer', () async {
    final app = Server(
      routes: const [],
      publicOrigin: Uri.parse('https://[::1]:8443'),
      functions: {
        'write': ServerFunctionBinding(
          ServerFunction<NoServerInput, int>(handler: (_) => 1),
        ),
      },
    );
    addTearDown(app.close);
    final response = await app.handle(
      ServerRequest.bytes(
        method: HttpMethod.post,
        uri: Uri.parse('http://internal.example/__odroe/functions/write'),
        headers: Headers.single({
          'referer': 'https://[::1]:8443/products',
          'x-odroe-server-function': 'true',
          'content-type': 'application/json',
        }),
        body: utf8.encode('{"data":null}'),
      ),
    );
    expect(response.status, 200, reason: await response.readText());
  });

  test(
    'default origin policy keeps the adapter requestedUri behavior',
    () async {
      var calls = 0;
      final app = Server(
        routes: const [],
        functions: {
          'write': ServerFunctionBinding(
            ServerFunction<NoServerInput, int>(handler: (_) => ++calls),
          ),
        },
      );
      final server = await IoServer.bind(app.handle, port: 0);
      addTearDown(() => IoServer.close(server, force: true));
      addTearDown(app.close);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final endpoint = Uri.parse(
        'http://127.0.0.1:${server.port}/__odroe/functions/write',
      );
      for (final forwarded in <bool>[false, true]) {
        final request = await client.postUrl(endpoint);
        request.headers
          ..contentType = ContentType.json
          ..set('host', 'public.example:8443')
          ..set('origin', 'https://public.example:8443')
          ..set('x-odroe-server-function', 'true');
        if (forwarded) {
          request.headers
            ..set('x-forwarded-proto', 'https')
            ..set('x-forwarded-host', 'public.example:8443');
        }
        request.write('{"data":null}');
        final response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, forwarded ? 200 : 403);
      }
      expect(calls, 1);
    },
  );
}
