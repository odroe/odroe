import 'package:odroe/config.dart';
import 'package:path/path.dart' as p;

import '../_internal/context.dart';
import 'create_page_node.dart';
import 'gen/manifest.dart';
import 'gen/write_server.dart';

extension type ExternalCommand._(Object _) {
  static build(OdroeConfig config, List<String> args) {
    final context = Context(config.root.path);
    final node = createPageNode(config.routes.path);
    final manifest = createServerManifest(config, node);

    writeServer(context, config, manifest);

    print('''
Success build Odroe server app to `${p.relative(context.serverPath)}`.

Next, Please use the following command to preview:

    `dart run ${p.relative(context.serverPath)}` - Using Dart command run server.
    `dart run odroe preview` - Using Odroe CLI perview.
''');
  }

  static dev(OdroeConfig config, List<String> args) {
    print('Dev.');
  }
}
