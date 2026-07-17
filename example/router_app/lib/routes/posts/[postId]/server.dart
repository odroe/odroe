import 'package:odroe/start.dart';

import 'route.dart' as definition;

final route = definition.route.server(load: (context) => const NoData());
