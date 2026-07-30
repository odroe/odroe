import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  // This verifies the JS binding shape, not Cloudflare's real D1 runtime.
  // A Wrangler local smoke remains the provider-level acceptance test.
  test('dart2js output passes the Node D1 fake-binding smoke', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'odroe_database_d1_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final output = File('${temporary.path}/fixture.js');

    final compile = await Process.run(_dartExecutable, <String>[
      'compile',
      'js',
      '-O4',
      '--no-source-maps',
      'test/database_d1/fixture.dart',
      '-o',
      output.path,
    ]).timeout(const Duration(seconds: 30));
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');

    final javaScript = await output.readAsString();
    expect(javaScript, isNot(matches(RegExp(r'\beval\s*\('))));
    expect(javaScript, isNot(matches(RegExp(r'\bnew\s+Function\s*\('))));

    final sources = <File>[
      File('lib/database_d1.dart'),
      for (final entity in Directory('lib/src/database_d1').listSync(
        recursive: true,
        followLinks: false,
      )..sort((left, right) => left.path.compareTo(right.path)))
        if (entity is File && entity.path.endsWith('.dart')) entity,
    ];
    final unsafeSources = <String>[
      for (final source in sources)
        if ((await source.readAsString()).contains('dart:js_interop_unsafe'))
          source.path,
    ];
    expect(unsafeSources, <String>['lib/src/database_d1/bind.dart']);
    final bindSource = await File(
      'lib/src/database_d1/bind.dart',
    ).readAsString();
    expect(bindSource, contains("callMethodVarArgs<JSObject>('bind'.toJS"));
    final joinedSources = (await Future.wait<String>(
      sources.map((source) => source.readAsString()),
    )).join();
    expect(
      RegExp(r'\bcallMethodVarArgs\b').allMatches(joinedSources),
      hasLength(1),
    );
    expect(joinedSources, isNot(matches(RegExp(r'\beval\s*\('))));
    expect(joinedSources, isNot(matches(RegExp(r'\bnew\s+Function\s*\('))));

    final smoke = await Process.run('node', <String>[
      'test/database_d1/smoke.mjs',
      output.path,
    ]).timeout(const Duration(seconds: 30));
    expect(smoke.exitCode, 0, reason: '${smoke.stdout}\n${smoke.stderr}');
    expect(smoke.stdout, contains('database_d1 fake-binding smoke passed'));
  });
}

String get _dartExecutable {
  if (Platform.resolvedExecutable.endsWith('/dart')) {
    return Platform.resolvedExecutable;
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    return '$flutterRoot/bin/cache/dart-sdk/bin/dart';
  }
  return 'dart';
}
