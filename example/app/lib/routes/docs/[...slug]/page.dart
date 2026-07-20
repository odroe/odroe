import 'package:flutter/material.dart';
import 'package:odroe/router_flutter.dart';

import 'route.dart' as definition;

final route = definition.route.page(
  build: (context) => Center(child: Text(context.params.slug.join('/'))),
);
