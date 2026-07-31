import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/dart_command_lock.dart';

void main() {
  test('dev serves the generated route tree and server functions', () async {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();

    final dartCommandLock = await acquireDartCommandLock();
    final publicDirectory = Directory('example/app/public').absolute;
    final publicDirectoryExisted = publicDirectory.existsSync();
    final publicAsset = File('${publicDirectory.path}/dev-asset.js');
    final publicAssetExisted = publicAsset.existsSync();
    final publicAssetBytes = publicAssetExisted
        ? publicAsset.readAsBytesSync()
        : null;
    publicDirectory.createSync();
    publicAsset.writeAsStringSync('source public asset');
    addTearDown(() {
      if (publicAssetExisted) {
        publicAsset.writeAsBytesSync(publicAssetBytes!, flush: true);
      } else if (publicAsset.existsSync()) {
        publicAsset.deleteSync();
      }
      if (!publicDirectoryExisted &&
          publicDirectory.existsSync() &&
          publicDirectory.listSync().isEmpty) {
        publicDirectory.deleteSync();
      }
    });
    final stalePage = File(
      'example/app/build/web/posts/42/index.html',
    ).absolute;
    final stalePageExisted = stalePage.existsSync();
    final stalePageBytes = stalePageExisted
        ? stalePage.readAsBytesSync()
        : null;
    final candidateDirectories = <Directory>[
      Directory('example/app/build/web').absolute,
      Directory('example/app/build/web/posts').absolute,
      stalePage.parent,
    ];
    final existingDirectories = <String>{
      for (final directory in candidateDirectories)
        if (directory.existsSync()) directory.path,
    };
    stalePage.parent.createSync(recursive: true);
    stalePage.writeAsStringSync('stale dev build');
    addTearDown(() {
      if (stalePageExisted) {
        stalePage.writeAsBytesSync(stalePageBytes!, flush: true);
      } else if (stalePage.existsSync()) {
        stalePage.deleteSync();
      }
      for (final directory in candidateDirectories.reversed) {
        if (!existingDirectories.contains(directory.path) &&
            directory.existsSync() &&
            directory.listSync().isEmpty) {
          directory.deleteSync();
        }
      }
    });
    late final Process process;
    try {
      process = await Process.start(
        dartExecutable,
        <String>[
          'run',
          'odroe',
          'dev',
          '--project',
          'example/app',
          '--server-only',
          '--port',
          '$port',
        ],
        environment: <String, String>{
          ...Platform.environment,
          'ODROE_FLUTTER_ORIGIN_FILE': '/stale/flutter-origin',
        },
      );
    } on Object {
      await dartCommandLock.release();
      rethrow;
    }
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
      try {
        process.kill(ProcessSignal.sigterm);
        await process.exitCode.timeout(const Duration(seconds: 10));
        await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
      } finally {
        await dartCommandLock.release();
      }
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
    final assetRequest = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/dev-asset.js'),
    );
    final assetResponse = await assetRequest.close();
    expect(assetResponse.statusCode, HttpStatus.ok);
    expect(
      await assetResponse.transform(utf8.decoder).join(),
      'source public asset',
    );
    final bootstrap = await File(
      'example/app/.dart_tool/odroe/server.dart',
    ).readAsString();
    expect(
      bootstrap,
      contains(
        "Platform.environment['ODROE_HOST'] ??\n"
        "      (platformPort == null ? '127.0.0.1' : '0.0.0.0')",
      ),
    );
    expect(
      bootstrap,
      contains(
        "Platform.environment['ODROE_PORT'] ??\n"
        "        platformPort ??",
      ),
    );
    expect(
      bootstrap,
      contains("developmentOriginFile == null || developmentOriginFile == ''"),
    );
    expect(bootstrap, contains('final appServer = app.createServer();'));
    expect(bootstrap, contains('appServer.handler'));
    expect(bootstrap, contains('onError: appServer.onError'));
    expect('app.createServer()'.allMatches(bootstrap), hasLength(1));

    final id = Uri.encodeComponent('posts.read-title');
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
