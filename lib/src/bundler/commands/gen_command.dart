import 'package:odroe/config.dart';

import '../../_internal/context.dart';
import '../gen/manifest.dart';
import '../gen/types.dart';
import '../gen/write_server.dart';

void genCommand(OdroeConfig config, Context context, PageNode node) {
  final manifest = createServerManifest(config, node);

  writeServer(context, config, manifest);
}
