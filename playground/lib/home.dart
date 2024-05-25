import 'package:flutter/material.dart' hide Route;
import 'package:odroe/odroe.dart';

import 'routes.dart';

Widget grid(Iterable<Route> routes) => setup(() {
      return () => GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            primary: false,
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 16 / 9,
            ),
            itemCount: routes.length,
            itemBuilder: (context, index) {
              final route = routes.elementAt(index);
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed(route.path),
                  child: Card(
                    elevation: 0,
                    child: Center(
                      child: Text(route.title),
                    ),
                  ),
                ),
              );
            },
          );
    });

Widget home() => setup(() {
      return () => Scaffold(
            appBar: AppBar(title: const Text('Odroe Playground')),
            body: ListView(
              children: [
                const ListTile(title: Text('Basics')),
                grid(basicRoutes.routes),
                const ListTile(title: Text('UI Widgets')),
                grid(uiRoutes.routes),
              ],
            ),
          );
    });
