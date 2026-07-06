import 'package:odroe/style.dart';
import 'package:test/test.dart';

import '_utils.dart';

void main() {
  test('creates typed term assignments', () {
    const term = Term<int>(Identifier('space.control_x'));

    final assignment = term(16);

    expect(assignment, isA<Assignment<int>>());
    expect(assignment.term, same(term));
    expect(assignment.value, 16);
  });

  test('stores binding assignments without resolving them', () {
    const fill = Term<String>(Identifier('color.action.fill'));
    const content = Term<String>(Identifier('color.action.content'));

    final binding = Binding(Identifier('light'), [
      fill('#006adc'),
      content('#ffffff'),
    ]);

    expect(binding.id.value, 'light');
    expect(binding.assignments, hasLength(2));
    expect(binding.assignments.first.term.id.value, 'color.action.fill');
    expect(binding.assignments.first.value, '#006adc');
  });

  test('copies assignments into an unmodifiable list', () {
    const term = Term<int>(Identifier('space.control_x'));
    final assignments = [term(16)];

    final binding = Binding(Identifier('light'), assignments);
    assignments.add(term(20));

    expect(binding.assignments, hasLength(1));
    expect(() => binding.assignments.add(term(24)), throwsUnsupportedError);
  });

  test('reports duplicate assignments inside one binding', () {
    const fill = Term<String>(Identifier('color.action.fill'));
    const sameFill = Term<String>(Identifier('color.action.fill'));
    const caseFill = Term<String>(Identifier('Color.Action.Fill'));

    final diagnostics = Binding(Identifier('light'), [
      fill('#006adc'),
      sameFill('#0055aa'),
      caseFill('#004488'),
    ]).validate();

    expect(
      diagnostics,
      containsDiagnostic(code: DiagnosticCodes.bindingDuplicateAssignment),
    );
    expect(
      diagnostics,
      containsDiagnostic(
        code: DiagnosticCodes.bindingDuplicateAssignmentIgnoringCase,
      ),
    );
  });
}
