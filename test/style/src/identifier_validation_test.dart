import 'package:odroe/src/style/identifier_validation.dart';
import 'package:odroe/style.dart';

void main() {
  final duplicateDiagnostics = validateIdentifierSet([
    Identifier('color.action.fill'),
    Identifier('color.action.fill'),
    Identifier('Color.Action.Fill'),
  ]);

  expectCode(
    duplicateDiagnostics,
    DiagnosticCodes.identifierDuplicate,
    'reports exact duplicates',
  );
  expectCode(
    duplicateDiagnostics,
    DiagnosticCodes.identifierDuplicateIgnoringCase,
    'reports case-insensitive duplicates',
  );
}

void expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

void expectCode(List<Diagnostic> diagnostics, String code, String message) {
  expect(diagnostics.any((diagnostic) => diagnostic.code == code), message);
}
