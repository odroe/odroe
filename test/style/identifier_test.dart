import 'package:odroe/style.dart';

void main() {
  final identifier = Identifier('color.action.fill');
  expect(identifier.value == 'color.action.fill', 'keeps the raw id value');
  expect(
    identifier.segments.join('/') == 'color/action/fill',
    'splits identifier segments',
  );
  expect(Identifier('button.tone').validate().isEmpty, 'accepts button.tone');

  expectCode(
    Identifier('').validate(),
    DiagnosticCodes.identifierEmpty,
    'reports empty identifiers',
  );
  expectCode(
    Identifier('color..action').validate(),
    DiagnosticCodes.identifierEmptySegment,
    'reports empty segments',
  );
  expectCode(
    Identifier('Color.Action').validate(),
    DiagnosticCodes.identifierInvalidSegment,
    'reports uppercase starts',
  );
  expectCode(
    Identifier('color action').validate(),
    DiagnosticCodes.identifierInvalidSegment,
    'reports whitespace',
  );
  expectCode(
    Identifier('color.action-fill').validate(),
    DiagnosticCodes.identifierInvalidSegment,
    'reports hyphenated segments',
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
