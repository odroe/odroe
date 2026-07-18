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

  test('server functions require a generated-code-visible declaration', () {
    final compiler = FileRouteCompiler(
      projectRoot: Directory('test/fixtures/invalid_server_functions').absolute,
    );
    final output = compiler.compile();

    expect(output.hasErrors, isTrue);
    expect(
      output.diagnostics.map((diagnostic) => diagnostic.toString()).join('\n'),
      contains('ServerFunction "_hidden" must be public'),
    );
  });

  test('server functions reject wire types the serializer cannot restore', () {
    final compiler = FileRouteCompiler(
      projectRoot: Directory('test/fixtures/invalid_server_functions').absolute,
    );
    final output = compiler.compile();

    expect(output.hasErrors, isTrue);
    expect(
      output.diagnostics.map((diagnostic) => diagnostic.toString()).join('\n'),
      contains('({int value}) is not JSON serializable'),
    );
  });

  test(
    'server function domain types must come from a prefixed shared import',
    () {
      final compiler = FileRouteCompiler(
        projectRoot: Directory('test/fixtures/unshared_server_type').absolute,
      );
      final output = compiler.compile();

      expect(output.hasErrors, isTrue);
      expect(
        output.diagnostics.single.toString(),
        contains(
          'uses client-visible type(s) LocalValue without an import prefix',
        ),
      );
    },
  );
}
