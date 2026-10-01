import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('identity key constructors and values stay type-safe', () async {
    final directory = Directory('test/app').absolute.path;
    final validPath = p.join(directory, 'key_fixture.dart');
    final invalidPath = p.join(directory, 'key_fixture.invalid');
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
      final diagnostics = (invalid as ResolvedUnitResult).diagnostics;
      final codes = diagnostics
          .map((diagnostic) => diagnostic.diagnosticCode.lowerCaseName)
          .toList();
      expect(
        codes.where((code) => code == 'const_with_non_const'),
        hasLength(3),
      );
      expect(
        codes.where((code) => code == 'argument_type_not_assignable'),
        hasLength(3),
      );
      expect(codes, contains('return_of_invalid_type_from_closure'));
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
