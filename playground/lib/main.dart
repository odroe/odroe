import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

import 'home.dart';
import 'routes.dart';

Widget app() => setup(() => () => MaterialApp(
      title: 'Odreo Playground',
      home: home(),
      routes: routes,
    ));

void main() => runApp(app());
