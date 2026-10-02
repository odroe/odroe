import 'dart:io';

import 'package:odroe/src/router_compiler/compiler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('generated client routes do not import the Press IO binding', () async {
    final project = await Directory.systemTemp.createTemp(
      'odroe-press-client-',
    );
    addTearDown(() => project.delete(recursive: true));

    await _write(project, 'lib/routes/route.dart', '''
import 'package:odroe/router.dart';

final route = AppRoute<NoParams, NoSearch, NoData>();
''');
    await _write(project, 'lib/routes/docs/[...slug]/route.dart', '''
import 'package:odroe/document.dart';
import 'package:odroe/press.dart';
import 'package:odroe/router.dart';

typedef Params = ({List<String> slug});

final route = AppRoute<Params, NoSearch, PressPage>(
  params: const PathParams<Params>.schema(),
).document((context) => context.data.toDocument());
''');
    await _write(project, 'lib/routes/docs/[...slug]/server.dart', '''
import 'package:odroe/press_io.dart';
import 'package:odroe/server.dart';

import 'route.dart' as definition;

final content = PressDirectory('content');

final route = definition.route.server(
  load: (context) async =>
      await content.page(context.params.slug) ?? (throw const NotFound()),
);
''');

    final output = FileRouteCompiler(projectRoot: project).compile();

    expect(output.diagnostics, isEmpty);
    expect(output.source, contains("routes/docs/[...slug]/route.dart"));
    expect(output.source, isNot(contains("routes/docs/[...slug]/server.dart")));
    expect(output.source, isNot(contains('package:odroe/press_io.dart')));
    expect(output.source, isNot(contains('dart:io')));
    expect(output.serverSource, contains("routes/docs/[...slug]/server.dart"));
  });
}

Future<void> _write(Directory root, String relative, String source) async {
  final file = File(p.join(root.path, relative));
  await file.parent.create(recursive: true);
  await file.writeAsString(source);
}
