import 'package:odroe/config.dart';

import 'create_page_node.dart';

extension type ExternalCommand._(Object _) {
  static build(OdroeConfig config, List<String> args) {
    final node = createPageNode(config.routes.path);
  }

  static dev(OdroeConfig config, List<String> args) {
    print('Dev.');
  }
}
