import 'package:odroe/src/style/identifier_validation.dart';
import 'package:odroe/style.dart';
import 'package:test/test.dart';

void main() {
  test('reports duplicate identifiers in one validation set', () {
    final duplicateDiagnostics = validateIdentifierSet([
      Identifier('color.action.fill'),
      Identifier('color.action.fill'),
      Identifier('Color.Action.Fill'),
    ]);

    expect(
      duplicateDiagnostics,
      containsDiagnosticCode(DiagnosticCodes.identifierDuplicate),
    );
    expect(
      duplicateDiagnostics,
      containsDiagnosticCode(DiagnosticCodes.identifierDuplicateIgnoringCase),
    );
  });
}

Matcher containsDiagnosticCode(String code) {
  return contains(
    isA<Diagnostic>().having((diagnostic) => diagnostic.code, 'code', code),
  );
}
