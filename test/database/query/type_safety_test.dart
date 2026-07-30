import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'column receivers preserve assignment and predicate value types',
    () async {
      final path = File(
        'test/database/query/type_fixture.invalid',
      ).absolute.path;
      final contexts = AnalysisContextCollection(
        includedPaths: <String>[path],
        sdkPath: _dartSdkPath(),
      );
      final SomeResolvedUnitResult result;
      try {
        result = await contexts
            .contextFor(path)
            .currentSession
            .getResolvedUnit(path);
      } finally {
        await contexts.dispose();
      }

      expect(result, isA<ResolvedUnitResult>());
      final diagnostics = (result as ResolvedUnitResult).diagnostics;
      expect(
        diagnostics.map(
          (diagnostic) => diagnostic.diagnosticCode.lowerCaseName,
        ),
        <String>[
          'argument_type_not_assignable',
          'argument_type_not_assignable',
          'argument_type_not_assignable',
        ],
      );
    },
  );
}

String _dartSdkPath() {
  final candidates = <String?>[
    Platform.environment['DART_SDK'],
    if (Platform.environment['FLUTTER_ROOT'] case final root?)
      p.join(root, 'bin', 'cache', 'dart-sdk'),
    if (p.basenameWithoutExtension(Platform.resolvedExecutable) == 'dart')
      p.dirname(p.dirname(Platform.resolvedExecutable)),
  ];
  final path = Platform.environment['PATH'];
  if (path != null) {
    for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
      if (directory.isEmpty) continue;
      candidates
        ..add(p.join(directory, 'cache', 'dart-sdk'))
        ..add(p.dirname(directory));
    }
  }
  for (final candidate in candidates) {
    if (candidate == null) continue;
    final root = p.normalize(p.absolute(candidate));
    if (File(p.join(root, 'lib', 'core', 'core.dart')).existsSync()) {
      return root;
    }
  }
  throw StateError('Could not locate the Dart SDK.');
}
