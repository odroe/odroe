import 'dart:convert';
import 'dart:io';

import 'package:odroe/server_io.dart';

Future<void> main(List<String> args) async {
  final javascript = File(args[0]).readAsStringSync();
  final report = File(args[1]);
  final server = await IoServer.bind((request) async {
    final path = request.uri.path;
    if (path == '/consumer.js') {
      return ServerResponse.text(javascript, contentType: 'text/javascript');
    }
    if (path == '/report') {
      report.writeAsStringSync(await utf8.decoder.bind(request.body).join());
      return ServerResponse.text('ok');
    }
    if (path.endsWith('/echo')) {
      return ServerResponse.json({
        'version': 1,
        'type': 'data',
        'data': {
          'path': path,
          'account': request.headers.value('x-account'),
          'input': jsonDecode(await utf8.decoder.bind(request.body).join()),
        },
      });
    }
    return ServerResponse.html('''<!doctype html>
<base href="/document/a/">
<script defer src="/consumer.js"></script>
<body>Ordinary RPC read consumer</body>''');
  }, port: 0);
  print('http://127.0.0.1:${server.port}');
}
