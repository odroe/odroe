import 'package:flutter/material.dart';
import 'package:odroe/router.dart';

import 'route.dart' as definition;

final route = definition.route.page(
  build: (context) => const Center(child: Text('Posts')),
);
