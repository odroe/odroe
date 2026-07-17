import 'package:odroe/start.dart';

import 'route.dart' as definition;

final route = definition.route.server();

// ignore: unused_element
final _hidden = ServerFunction<NoServerInput, int>(handler: (_) => 1);
