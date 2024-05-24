import 'package:flutter/widgets.dart';

import 'basics/counter.dart';
import 'home.dart';
import 'ui/link.dart';

typedef PageSetupWidget = Widget Function();

extension on PageSetupWidget {
  WidgetBuilder toBuilder() => (_) => this();
}

class Route {
  const Route(
      {required this.widget,
      required this.path,
      required this.title,
      this.desc});

  final String path;
  final String title;
  final String? desc;
  final PageSetupWidget widget;
}

class GroupedRoutes {
  const GroupedRoutes(this.title, this.routes);

  final String title;
  final Iterable<Route> routes;
}

extension on GroupedRoutes {
  Map<String, WidgetBuilder> toRoutes() {
    final entrise = this
        .routes
        .map((route) => MapEntry(route.path, route.widget.toBuilder()));

    return Map.fromEntries(entrise);
  }
}

const basicRoutes = GroupedRoutes('Basics', [
  Route(path: '/basics/counter', title: 'Counter', widget: counter),
]);

const uiRoutes = GroupedRoutes('UI', [
  Route(path: '/ui/link', title: 'Link', widget: linkExample),
]);

final routes = <String, WidgetBuilder>{
  ...basicRoutes.toRoutes(),
  ...uiRoutes.toRoutes(),
};
