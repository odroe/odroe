import 'dart:io';

import 'package:path/path.dart' as p;

import '../../_internal/context.dart';
import '../../config/odroe_config.dart';
import '../types.dart';
import '../utils/file_to_route.dart';

void writeServer(Context context, OdroeConfig config, Manifest manifest) {
  final server = File(context.serverPath);
  if (server.existsSync()) {
    server.deleteSync();
  }
  server.createSync(recursive: true);

  final configImportURL = p
      .relative(context.configPath, from: p.dirname(server.path))
      .replaceAll('\\', '/');

  final code = '''
import 'dart:io';

import 'package:spry/spry.dart';
import 'package:spry/io.dart';

import '$configImportURL' as c;
${_importRoutes(p.dirname(server.path), manifest)}
main() async {
  final config = await c.config;
  final app = createSpry();

${_registerRoutes(config.routes.path, manifest)}
  final handler = toIOHandler(app);
  final server = await HttpServer.bind(config.server.host, config.server.port);

  server.listen(handler);

  print('🎉 Server listen on http:\${config.server.host}:\${config.server.port}');
}
''';

  server.writeAsStringSync(code);
}

String _registerRoutes(String root, Manifest manifest) {
  final buffer = StringBuffer();
  for (final (index, endpoint) in manifest.indexed) {
    if (endpoint.fallback != null) {
      buffer.write('  app.all(\'');
      buffer.write(fileToRoute(root, endpoint.path));
      buffer.write('\', i');
      buffer.write(index);
      buffer.write('.');
      buffer.write(endpoint.fallback);
      buffer.writeln(');');
    }

    for (final method in endpoint.methods) {
      buffer.write('  app.on(\'');
      buffer.write(method.toUpperCase());
      buffer.write('\', \'');
      buffer.write(fileToRoute(root, endpoint.path));
      buffer.write('\', i');
      buffer.write(index);
      buffer.write('.');
      buffer.write(method);
      buffer.writeln(');');
    }
  }

  return buffer.toString();
}

String _importRoutes(String from, Manifest manifest) {
  final buffer = StringBuffer();
  for (final (index, endpoint) in manifest.indexed) {
    buffer.write('import \'');
    buffer.write(p.relative(endpoint.path, from: from).replaceAll('\\', '/'));
    buffer.write('\' as i');
    buffer.write(index);
    buffer.writeln(';');
  }

  return buffer.toString();
}
