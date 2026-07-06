import 'package:odroe/style.dart';
import 'package:test/test.dart';

import '_utils.dart';

void main() {
  test('keeps the raw identifier value', () {
    const identifier = Identifier('color.action.fill');

    expect(identifier.value, 'color.action.fill');
  });

  test('splits dot-separated segments', () {
    const identifier = Identifier('color.action.fill');

    expect(identifier.segments, ['color', 'action', 'fill']);
  });

  test('accepts valid identifiers', () {
    expect(const Identifier('button.tone').validate(), isEmpty);
  });

  test('reports invalid identifier formats', () {
    expect(
      const Identifier('').validate(),
      containsDiagnosticCode(DiagnosticCodes.identifierEmpty),
    );
    expect(
      const Identifier('color..action').validate(),
      containsDiagnosticCode(DiagnosticCodes.identifierEmptySegment),
    );
    expect(
      const Identifier('Color.Action').validate(),
      containsDiagnosticCode(DiagnosticCodes.identifierInvalidSegment),
    );
    expect(
      const Identifier('color action').validate(),
      containsDiagnosticCode(DiagnosticCodes.identifierInvalidSegment),
    );
    expect(
      const Identifier('color.action-fill').validate(),
      containsDiagnosticCode(DiagnosticCodes.identifierInvalidSegment),
    );
  });
}
