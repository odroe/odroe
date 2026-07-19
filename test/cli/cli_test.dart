import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('dev serves the generated route tree and server functions', () async {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();

    final process = await Process.start('dart', <String>[
      'run',
      'odroe',
      'dev',
      '--project',
      'example/app',
      '--server-only',
      '--port',
      '$port',
    ]);
    final output = StringBuffer();
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .listen(output.write)
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(output.write)
        .asFuture<void>();
    addTearDown(() async {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(const Duration(seconds: 10));
      await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
    });

    final client = HttpClient();
    addTearDown(client.close);
    String? page;
    Object? lastError;
    for (var attempt = 0; attempt < 80; attempt++) {
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/posts/42?preview=true'),
        );
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        page = await response.transform(utf8.decoder).join();
        if (response.statusCode == 200) break;
      } on Object catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(
      page,
      contains('"location":"/posts/42?preview=true"'),
      reason: '$lastError\n$output',
    );

    final id = Uri.encodeComponent(
      'lib/routes/posts/[postId]/server.dart#readTitle',
    );
    final rpc = await client.getUrl(
      Uri.parse(
        'http://127.0.0.1:$port/__odroe/functions/$id'
        '?payload=%7B%22data%22%3A7%7D',
      ),
    );
    rpc.headers.set('origin', 'http://127.0.0.1:$port');
    rpc.headers.set('x-odroe-server-function', 'true');
    final rpcResponse = await rpc.close();
    final rpcBody = await rpcResponse.transform(utf8.decoder).join();
    expect(rpcResponse.statusCode, 200, reason: rpcBody);
    expect(jsonDecode(rpcBody), <String, Object?>{
      'version': 1,
      'type': 'data',
      'data': 'Post 7',
    });
  });
}
