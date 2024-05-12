import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

import 'routes.dart';

final demo = WeakMap();

dynamic key = {};

Widget app() => setup(() {
      final pre = key;
      demo[key] = true;
      key = {1: 2};

      print(demo[pre]);

      return MaterialApp(
        title: 'Odroe Examples',
        initialRoute: initialRoute,
        routes: routes,
      );
    });

void main(List<String> args) {
  runApp(app());
}
