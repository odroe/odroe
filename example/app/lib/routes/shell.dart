import 'package:flutter/material.dart';
import 'package:odroe/router.dart';

final route = shellRoute(
  build: (context, navigator) => Scaffold(
    appBar: AppBar(title: const Text('Odroe Router')),
    body: navigator,
  ),
);
