import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

import 'routes.dart';
import 'theme.dart';

Widget app() => setup(() {
      return MaterialApp(
        theme: $store(lightThemeStore),
        darkTheme: $store(darkThemeStore),
        themeMode: $store(modeThemeStore),
        title: 'Odroe Examples',
        initialRoute: initialRoute,
        routes: routes,
      );
    });

void main(List<String> args) {
  runApp(app());
}
