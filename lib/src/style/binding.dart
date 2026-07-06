import 'diagnostic.dart';
import 'identifier.dart';

/// A typed vocabulary term that can be assigned by a [Binding].
///
/// Terms are semantic design words, not resolved token values. For example,
/// `color.action.fill` can be represented as a `Term<ColorValue>` and assigned
/// differently by light, dark, brand, or density bindings.
final class Term<T> {
  /// Creates a term with a stable [id].
  const Term(this.id);

  /// The stable authoring name of this term.
  final Identifier id;

  /// Creates an assignment for this term.
  ///
  /// This method preserves the term's value type in the returned
  /// [Assignment]. It does not validate or resolve the value.
  Assignment<T> call(T value) {
    return Assignment<T>(this, value);
  }
}

/// One typed value assigned to a [Term].
///
/// Assignments are declaration data. They do not resolve other terms, normalize
/// values, or perform platform conversion.
final class Assignment<T> {
  /// Creates an assignment from [term] to [value].
  const Assignment(this.term, this.value);

  /// The term being assigned.
  final Term<T> term;

  /// The value assigned to [term].
  final T value;
}

/// A named set of concrete values for vocabulary terms.
///
/// A binding can represent a theme, mode, brand, density, or other environment
/// selection. Terms are not resolved when the binding is declared; resolution is
/// a later style operation that chooses one binding and reads the assignments.
final class Binding {
  /// Creates a binding with a stable [id] and concrete [assignments].
  ///
  /// The assignments are copied into an unmodifiable list so validation and
  /// resolution see a stable declaration after construction.
  Binding(this.id, Iterable<Assignment<Object?>> assignments)
    : assignments = List.unmodifiable(assignments);

  /// The stable authoring name of this binding.
  final Identifier id;

  /// The assignments declared by this binding.
  final List<Assignment<Object?>> assignments;

  /// Returns diagnostics for this binding declaration.
  ///
  /// This validates the binding identifier, each assigned term identifier, and
  /// repeated term assignments inside this binding. It does not check whether
  /// the terms are declared in a vocabulary or whether all required terms have
  /// been assigned.
  List<Diagnostic> validate() {
    final diagnostics = <Diagnostic>[
      ...id.validate(
        target: DiagnosticTarget(kind: 'binding', name: id.value),
      ),
    ];
    final seen = <String, Assignment<Object?>>{};
    final seenIgnoringCase = <String, Assignment<Object?>>{};

    for (final assignment in assignments) {
      final termId = assignment.term.id;
      final target = DiagnosticTarget(kind: 'assignment', name: termId.value);

      diagnostics.addAll(termId.validate(target: target));

      final duplicate = seen[termId.value];
      if (duplicate != null) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCodes.bindingDuplicateAssignment,
            target: target,
            message:
                'Binding `${id.value}` assigns term `${termId.value}` more '
                'than once.',
          ),
        );
      } else {
        seen[termId.value] = assignment;
      }

      final folded = termId.value.toLowerCase();
      final caseDuplicate = seenIgnoringCase[folded];
      if (caseDuplicate != null &&
          caseDuplicate.term.id.value != termId.value) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCodes.bindingDuplicateAssignmentIgnoringCase,
            target: target,
            message:
                'Binding `${id.value}` assigns `${termId.value}` and '
                '`${caseDuplicate.term.id.value}`, which differ only by '
                'letter case.',
          ),
        );
      } else {
        seenIgnoringCase[folded] = assignment;
      }
    }

    return diagnostics;
  }
}
