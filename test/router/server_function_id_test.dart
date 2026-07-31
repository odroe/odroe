import 'dart:io';

import 'package:odroe/src/router_compiler/compiler.dart';
import 'package:test/test.dart';

void main() {
  group('ServerFunction wire id', () {
    late _RouteProject project;

    setUp(() {
      project = _RouteProject.create();
    });

    tearDown(() {
      project.dispose();
    });

    test('uses an explicit id on both sides and keeps it after a rename', () {
      project.writeFunctions(
        _serverFunction(name: 'readPost', id: "'posts.read'"),
      );
      final before = project.compile();

      expect(before.diagnostics, isEmpty);
      expect(before.source, contains('id: "posts.read"'));
      expect(
        before.serverSource,
        contains('"posts.read": ServerFunctionBinding('),
      );
      expect(before.source, contains('get readPost'));

      project.writeFunctions(
        _serverFunction(name: 'renamedReadPost', id: "'posts.read'"),
      );
      final after = project.compile();

      expect(after.diagnostics, isEmpty);
      expect(after.source, contains('id: "posts.read"'));
      expect(
        after.serverSource,
        contains('"posts.read": ServerFunctionBinding('),
      );
      expect(after.source, contains('get renamedReadPost'));
      expect(
        after.source,
        isNot(contains('lib/routes/server.dart#renamedReadPost')),
      );
    });

    test('rejects duplicate explicit ids', () {
      project.writeFunctions('''
${_serverFunction(name: 'readPost', id: "'posts.read'")}
${_serverFunction(name: 'updatePost', id: "'posts.read'")}
''');

      final output = project.compile();
      final messages = output.diagnostics
          .map((diagnostic) => diagnostic.message)
          .join('\n')
          .toLowerCase();

      expect(output.hasErrors, isTrue);
      expect(messages, contains('duplicate id'));
      expect(messages, contains('posts.read'));
    });

    test('rejects explicit and fallback collisions across route files', () {
      project.writeFunctions(
        _serverFunction(
          name: 'rootFunction',
          id: "'lib/routes/child/server.dart#readChild'",
        ),
      );
      project.writeChildFunctions(_serverFunction(name: 'readChild'));

      final output = project.compile();
      final messages = output.diagnostics
          .map((diagnostic) => diagnostic.message)
          .join('\n');

      expect(output.hasErrors, isTrue);
      expect(messages, contains('lib/routes/child/server.dart#readChild'));
      expect(messages, contains('rootFunction'));
      expect(messages, contains('readChild'));
      expect(messages, contains('lib/routes/server.dart'));
    });

    test('accepts adjacent string literals', () {
      project.writeFunctions(
        _serverFunction(name: 'readPost', id: "'posts.' 'read'"),
      );

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(output.source, contains('id: "posts.read"'));
      expect(
        output.serverSource,
        contains('"posts.read": ServerFunctionBinding('),
      );
    });

    test('rejects non-literal and empty ids', () {
      project.writeFunctions('''
const functionId = 'posts.read';

${_serverFunction(name: 'readPost', id: 'functionId')}
''');
      var output = project.compile();

      expect(output.hasErrors, isTrue);
      expect(
        output.diagnostics.map((diagnostic) => diagnostic.message),
        contains('ServerFunction "readPost" id must be a string literal.'),
      );

      project.writeFunctions(_serverFunction(name: 'readPost', id: "''"));
      output = project.compile();

      expect(output.hasErrors, isTrue);
      expect(
        output.diagnostics.map((diagnostic) => diagnostic.message),
        contains('ServerFunction "readPost" id must not be empty.'),
      );
    });

    test('keeps the path-based id when id is omitted', () {
      project.writeFunctions(_serverFunction(name: 'readPost'));

      final output = project.compile();
      const fallback = 'lib/routes/server.dart#readPost';

      expect(output.diagnostics, isEmpty);
      expect(output.source, contains('id: "$fallback"'));
      expect(
        output.serverSource,
        contains('"$fallback": ServerFunctionBinding('),
      );
    });

    test('eagerly validates Iterable input before the handler starts', () {
      project.writeFunctions(
        _serverFunction(name: 'readValues', input: 'Iterable<int>'),
      );

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(output.serverSource, contains('value as List'));
      expect(output.serverSource, contains('item as int'));
      expect(output.serverSource, contains('.toList(growable: false)'));
    });
  });
}

String _serverFunction({
  required String name,
  String? id,
  String input = 'int',
}) =>
    '''
final $name = ServerFunction<$input, String>(
  ${id == null ? '' : 'id: $id,'}
  handler: (_) => 'ok',
);
''';

final class _RouteProject {
  _RouteProject._(this.root, this.serverFile);

  factory _RouteProject.create() {
    final root = Directory.systemTemp.createTempSync(
      'odroe-server-function-id-',
    );
    final routes = Directory('${root.path}/lib/routes')
      ..createSync(recursive: true);
    File('${routes.path}/route.dart').writeAsStringSync('''
import 'package:odroe/router.dart';

final route = AppRoute<NoParams, NoSearch, NoData>();
''');
    return _RouteProject._(root, File('${routes.path}/server.dart'));
  }

  final Directory root;
  final File serverFile;

  void writeFunctions(String functions) {
    serverFile.writeAsStringSync('''
import 'package:odroe/router.dart';
import 'package:odroe/rpc.dart';
import 'package:odroe/server.dart';

import 'route.dart' as definition;

final route = definition.route.server();

$functions
''');
  }

  void writeChildFunctions(String functions) {
    final routes = Directory('${root.path}/lib/routes/child')
      ..createSync(recursive: true);
    File('${routes.path}/route.dart').writeAsStringSync('''
import 'package:odroe/router.dart';

final route = AppRoute<NoParams, NoSearch, NoData>();
''');
    File('${routes.path}/server.dart').writeAsStringSync('''
import 'package:odroe/router.dart';
import 'package:odroe/rpc.dart';
import 'package:odroe/server.dart';

import 'route.dart' as definition;

final route = definition.route.server();

$functions
''');
  }

  FileRouteOutput compile() => FileRouteCompiler(projectRoot: root).compile();

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}
