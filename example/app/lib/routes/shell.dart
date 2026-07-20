import 'package:flutter/material.dart';
import 'package:odroe/router_flutter.dart';

import 'route.dart' as definition;

final route = definition.route.shell(
  build: (context, navigator) => Scaffold(
    appBar: AppBar(title: const Text('Odroe Router')),
    body: navigator,
  ),
);
