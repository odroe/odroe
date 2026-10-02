import 'package:odroe/server.dart';

import '../../../content.dart';
import 'route.dart' as definition;

final route = definition.route.server(
  load: (context) => loadDocs(context.params.slug),
);
