import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/router_compiler.dart';

void main() {
  test(
    'reports source-oriented contract diagnostics without writing output',
    () {
      final compiler = FileRouteCompiler(
        projectRoot: Directory('test/fixtures/invalid_file_routes').absolute,
      );
      final output = compiler.compile();

      expect(output.hasErrors, isTrue);
      expect(output.source, isEmpty);
      expect(
        output.diagnostics.single.toString(),
        contains('Params fields {slug} must exactly match path fields {id}.'),
      );
      expect(compiler.outputFile.existsSync(), isFalse);
    },
  );

  test('rejects ambiguous URLs hidden behind route groups', () {
    final compiler = FileRouteCompiler(
      projectRoot: Directory('test/fixtures/ambiguous_file_routes').absolute,
    );
    final output = compiler.compile();

    expect(output.hasErrors, isTrue);
    expect(
      output.diagnostics.single.toString(),
      contains('Terminal route pattern "/profile" conflicts'),
    );
  });
}
