import 'dart:io';

import 'package:path/path.dart' as p;

import '../../_internal/context.dart';
import '../../config/odroe_config.dart';
import 'types.dart';
import 'utils/file_to_route.dart';
import 'utils/gen_import_code.dart';

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

  await config.server.setup?.call(app);

  ${_registerRoutes(config.routes.path, config.base, manifest)}

  final handler = toIOHandler(app);
  final server = await HttpServer.bind(config.server.host, config.server.port);

  server.listen(handler);

  print('🎉 Server listen on http:\${config.server.host}:\${config.server.port}');
}
''';

  server.writeAsStringSync(code);
}

const _routeImportPrefix = 'r';

String _registerRoutes(String root, String base, Manifest manifest) {
  final codes = <String>[];
  final buffer = StringBuffer();

  base = base.endsWith('/') ? base : '$base/';

  for (final (index, endpoint) in manifest.indexed) {
    if (endpoint.fallback != null) {
      buffer.clear();
      buffer.write('  app.all(\'');
      buffer.write(base);
      buffer.write(fileToRoute(root, endpoint.path));
      buffer.write('\', ');
      buffer.write(_routeImportPrefix);
      buffer.write(index);
      buffer.write('.');
      buffer.write(endpoint.fallback);
      buffer.write(');');

      codes.add(buffer.toString());
    }

    for (final method in endpoint.methods) {
      buffer.clear();
      buffer.write('  app.on(\'');
      buffer.write(method.toUpperCase());
      buffer.write('\', \'');
      buffer.write(base);
      buffer.write(fileToRoute(root, endpoint.path));
      buffer.write('\', ');
      buffer.write(_routeImportPrefix);
      buffer.write(index);
      buffer.write('.');
      buffer.write(method);
      buffer.write(');');

      codes.add(buffer.toString());
    }
  }

  return codes.join(Platform.lineTerminator).trimLeft();
}

String _importRoutes(String from, Manifest manifest) {
  return genImportCode(manifest.map((e) => e.path), from, _routeImportPrefix);
}
