@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'public scalar factories and route values infer precise types',
    () async {
      final temp = Directory.systemTemp.createTempSync('odroe-route-types-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final source = File('.dart_tool/package_config.json').absolute;
      final config = jsonDecode(source.readAsStringSync()) as Map;
      for (final package in config['packages'] as List) {
        package['rootUri'] = source.uri
            .resolve(package['rootUri'] as String)
            .toString();
      }
      final target = File('${temp.path}/.dart_tool/package_config.json');
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(jsonEncode(config));
      File('${temp.path}/pubspec.yaml').writeAsStringSync(
        'name: route_type_consumer\nenvironment:\n  sdk: ^3.10.0\n',
      );
      File('${temp.path}/analysis_options.yaml').writeAsStringSync('''
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
''');
      File('${temp.path}/positive.dart').writeAsStringSync("""
import 'package:odroe/router.dart';
void main() {
  final path = PathParams.integer('postId');
  final filter = SearchParams.optionalInteger('authorId');
  final page = SearchParams.integer('page', defaults: 1);
  final int id = path.decode({'postId':['42']});
  final int? author = filter.decode({}).value;
  final bool oddPage = page.decode({}).value.isOdd;
  final route = AppRoute<int, int?, NoData>(path: '/posts/:postId', params: path, search: filter);
  final RouteRef<int, int?, NoData> ref = route.ref(params: id, search: author);
  final RouteMatch<int, int?, NoData> match = RouteMatcher([route]).match(ref.destination.uri)!.leaf(route);
  print([match.params.isEven, match.search?.isOdd, oddPage]);
}
""");
      final positive = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        '--fatal-infos',
        'positive.dart',
      ], workingDirectory: temp.path);
      expect(
        positive.exitCode,
        0,
        reason: '${positive.stdout}\n${positive.stderr}',
      );
      File('${temp.path}/negative.dart').writeAsStringSync("""
import 'package:odroe/router.dart';
void bad() {
  final path = PathParams.integer('postId');
  final filter = SearchParams.optionalInteger('authorId');
  final page = SearchParams.integer('page', defaults: 1);
  final String wrongPath = path.decode({'postId':['42']});
  path.encode('42');
  final String wrongPage = page.decode({}).value;
  final int missing = filter.decode({}).value;
  filter.encode('7');
  final route = AppRoute<int,int?,NoData>(path: '/posts/:postId',params:path,search:filter);
  route.to(params:'42',search:'7');
  final String wrongMatch = RouteMatcher([route]).match(Uri.parse('/posts/42'))!.leaf(route).params;
  print([wrongPath,wrongPage,missing,wrongMatch]);
}
""");
      final negative = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        '--format=machine',
        'negative.dart',
      ], workingDirectory: temp.path);
      expect(negative.exitCode, isNot(0));
      final diagnostics = '${negative.stdout}\n${negative.stderr}';
      expect(
        diagnostics.split('\n').where((line) => line.startsWith('ERROR|')),
        hasLength(8),
        reason: diagnostics,
      );
      expect(
        RegExp('INVALID_ASSIGNMENT').allMatches(diagnostics).length,
        4,
        reason: diagnostics,
      );
      expect(
        RegExp('ARGUMENT_TYPE_NOT_ASSIGNABLE').allMatches(diagnostics).length,
        4,
        reason: diagnostics,
      );
    },
  );
}
