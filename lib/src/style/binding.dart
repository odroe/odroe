import 'diagnostic.dart';
import 'identifier.dart';

/// A typed word in a design vocabulary.
///
/// Terms give semantic names to values without choosing the value. A design
/// system can declare one term and assign different values to it in each
/// [Binding]:
///
/// ```dart
/// const actionFill = Term<String>(Identifier('color.action.fill'));
///
/// final light = Binding(Identifier('light'), [
///   actionFill('#006adc'),
/// ]);
///
/// final dark = Binding(Identifier('dark'), [
///   actionFill('#8ab4ff'),
/// ]);
/// ```
///
/// The type argument is part of the authoring contract. A
/// `Term<double>` creates `Assignment<double>` values, while a `Term<String>`
/// creates `Assignment<String>` values. The core does not prescribe concrete
/// value classes in this slice so applications can start with ordinary Dart
/// values and move to richer value objects later.
final class Term<T> {
  /// Creates a vocabulary term with a stable [id].
  const Term(this.id);

  /// The authoring name used to match assignments, diagnostics, and future
  /// resolution.
  final Identifier id;

  /// Creates an [Assignment] that gives this term a concrete value.
  ///
  /// Calling a term is only declaration syntax. It does not validate [value],
  /// read a binding, or resolve references to other terms.
  ///
  /// ```dart
  /// const controlX = Term<int>(Identifier('space.control_x'));
  ///
  /// final assignment = controlX(16);
  /// ```
  Assignment<T> call(T value) {
    return Assignment<T>(this, value);
  }
}

/// A concrete value for one [Term].
///
/// Assignments are the entries inside a [Binding]. They preserve both the term
/// and the authored value so later validation and resolution can explain where
/// a value came from.
///
/// An assignment is not a resolved token. It does not normalize colors,
/// calculate inherited values, or convert to platform-specific output.
final class Assignment<T> {
  /// Creates an authored value for [term].
  const Assignment(this.term, this.value);

  /// The term whose value is declared by this assignment.
  final Term<T> term;

  /// The authored value for [term].
  final T value;
}

/// A named collection of term values.
///
/// A binding usually represents a theme, color mode, brand, density, or other
/// environment choice. It is only a declaration. Creating a binding does not
/// resolve terms, merge appearances, or choose a platform representation.
///
/// ```dart
/// const fill = Term<String>(Identifier('color.action.fill'));
/// const radius = Term<double>(Identifier('radius.control'));
///
/// final light = Binding(Identifier('light'), [
///   fill('#006adc'),
///   radius(8),
/// ]);
/// ```
final class Binding {
  /// Creates a binding with a stable [id].
  ///
  /// [assignments] is copied into an unmodifiable list. Mutating the source
  /// iterable after construction will not change the binding.
  Binding(this.id, Iterable<Assignment<Object?>> assignments)
    : assignments = List.unmodifiable(assignments);

  /// The authoring name used to select this binding.
  final Identifier id;

  /// The term values declared by this binding.
  ///
  /// The order is preserved for diagnostics, but duplicate terms are reported
  /// by [validate] instead of being resolved by declaration order.
  final List<Assignment<Object?>> assignments;

  /// Returns declaration diagnostics for this binding.
  ///
  /// Validation is intentionally local to the binding. It checks:
  ///
  /// * the binding identifier;
  /// * each assigned term identifier;
  /// * repeated term assignments inside this binding.
  ///
  /// It does not check whether a term belongs to a vocabulary, whether every
  /// expected term has a value, or whether assigned values are usable by a
  /// platform adapter. Those checks need a larger owner such as a design
  /// manifest.
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
