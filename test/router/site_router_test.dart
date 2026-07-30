import 'dart:io';

import 'package:odroe/src/router_compiler/compiler.dart';
import 'package:test/test.dart';

void main() {
  test('official site server imports only route definitions it uses', () {
    final project = Directory('sites/odroe.dev').absolute;
    final compiler = FileRouteCompiler(projectRoot: project);
    final output = compiler.compile();

    expect(output.diagnostics, isEmpty);
    expect(output.staticRoutes, contains('/404.html'));
    expect(
      output.serverSource,
      isNot(contains("import 'routes/docs/route.dart'")),
    );
    expect(
      output.serverSource,
      contains("import 'routes/docs/[...slug]/route.dart'"),
    );
  });
}
