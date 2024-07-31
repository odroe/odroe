import 'package:odroe/config.dart';
import 'package:path/path.dart' as p;

import '../_internal/context.dart';
import 'commands/gen_command.dart';
import 'create_page_node.dart';
import 'gen/types.dart';

extension type ExternalCommand._(Object _) {
  static generate(OdroeConfig config, List<String> args) {
    final (context, _) = _createCtxAndGenerate(config);

    print('''
Success generate Odroe server app to `${p.relative(context.serverPath)}`.

Next, Please use the following command to preview:

    odroe preview
''');
  }

  static build(OdroeConfig config, List<String> args) {
    final (context, _) = _createCtxAndGenerate(config);
  }

  static dev(OdroeConfig config, List<String> args) {
    final (context, _) = _createCtxAndGenerate(config);
  }
}

(Context, PageNode) _createCtxAndGenerate(OdroeConfig config) {
  final context = Context(config.root.path);
  final node = createPageNode(config.routes.path);

  genCommand(config, context, node);

  return (context, node);
}
