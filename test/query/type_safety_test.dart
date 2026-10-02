import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/analyzer_diagnostics.dart';

void main() {
  test('query keys preserve options, state, and data types', () async {
    final directory = Directory('test/query').absolute.path;
    final validPath = p.join(directory, 'type_fixture.dart');
    final invalidPath = p.join(directory, 'type_fixture.invalid');
    final contexts = AnalysisContextCollection(
      includedPaths: <String>[directory],
      sdkPath: _dartSdkPath(),
    );
    try {
      final valid = await contexts
          .contextFor(validPath)
          .currentSession
          .getResolvedUnit(validPath);
      final invalid = await contexts
          .contextFor(invalidPath)
          .currentSession
          .getResolvedUnit(invalidPath);

      expect(valid, isA<ResolvedUnitResult>());
      expect((valid as ResolvedUnitResult).diagnostics, isEmpty);
      expect(invalid, isA<ResolvedUnitResult>());
      expect(
        (invalid as ResolvedUnitResult).diagnostics.map(diagnosticCodeName),
        <String>[
          'argument_type_not_assignable',
          'argument_type_not_assignable',
          'argument_type_not_assignable',
          'argument_type_not_assignable',
          'argument_type_not_assignable',
        ],
      );
    } finally {
      await contexts.dispose();
    }
  });
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
