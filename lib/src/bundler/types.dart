enum RouteFile {
  page('page.dart'),
  pageServer('page.server.dart'),
  layout('layout.dart'),
  layoutServer('layout.server.dart'),
  error('error.dart'),
  server('server.dart')
  //---------------------------------------
  ;

  final String name;
  const RouteFile(this.name);
}

class PageNode {
  PageNode(this.id);

  final String id;
  final files = <RouteFile>{};
  PageNode? parent;
  final children = <PageNode>[];
}
