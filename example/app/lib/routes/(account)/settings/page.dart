import 'package:flutter/material.dart';
import 'package:odroe/router_flutter.dart';

import 'route.dart' as definition;

final route = definition.route.page(
  build: (context) => const Center(child: Text('Account settings')),
);
