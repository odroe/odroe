import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

import 'routes.dart';

Widget app() => setup(() {
      return MaterialApp(
        title: 'Odroe Examples',
        initialRoute: initialRoute,
        routes: routes,
      );
    });

void main(List<String> args) {
  runApp(app());
}
