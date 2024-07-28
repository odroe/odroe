import 'dart:io';

import 'package:path/path.dart' as path;

import 'gen/types.dart';

PageNode createPageNode(String id, [PageNode? parent]) {
  final node = PageNode(id)..parent = parent;
  for (final file in RouteFile.values) {
    if (File(path.join(id, file.name)).existsSync()) {
      node.files.add(file);
    }
  }

  if (node.files.contains(RouteFile.server) &&
      (node.files.contains(RouteFile.page) ||
          node.files.contains(RouteFile.pageServer))) {
    final String name = node.files.contains(RouteFile.page)
        ? RouteFile.page.name
        : RouteFile.pageServer.name;

    throw Exception(
        '`${RouteFile.server.name}`` is mutually exclusive with either `$name`.');
  }

  for (final directory in Directory(id).listSync().whereType<Directory>()) {
    node.children.add(createPageNode(directory.path, node));
  }

  return node;
}
