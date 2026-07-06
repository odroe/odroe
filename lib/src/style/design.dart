import 'axis.dart';
import 'binding.dart';
import 'condition.dart';
import 'contract.dart';
import 'diagnostic.dart';
import 'identifier.dart';
import 'state.dart';
import 'style.dart';

/// A platform-neutral manifest for one style system.
///
/// A design gathers the declarations that need to agree with each other: the
/// typed terms object a system authors against, the bindings that give those
/// terms values, the styles that consume appearances and contracts, and the
/// custom policies a project wants to enforce.
///
/// ```dart
/// const t = AppTerms();
///
/// final design = Design(
///   terms: t,
///   bindings: [
///     Binding(Identifier('light'), [
///       t.color.action.fill(const Color(0xff006adc)),
///       t.radius.control(8.px),
///     ]),
///   ],
///   styles: [
///     Style<void>(
///       id: Identifier('button'),
///       root: Appearance(),
///     ),
///   ],
///   policies: const [NoRawColorPolicy()],
/// );
///
/// final diagnostics = design.validate();
/// ```
///
/// Validation stays in the core model. It reports missing declarations and
/// policy findings, but it does not project the design to CSS, Flutter, Material,
/// Jaspr, or any other platform.
final class Design {
  /// Creates a style design manifest.
  ///
  /// All collections are copied into immutable lists. Mutating a source list
  /// after construction will not change the design being validated.
  Design({
    required Vocabulary terms,
    Iterable<Binding> bindings = const [],
    Iterable<Style> styles = const [],
    Iterable<Policy> policies = const [],
  }) : terms = terms,
       vocabulary = List.unmodifiable(terms.terms),
       bindings = List.unmodifiable(bindings),
       styles = List.unmodifiable(styles),
       policies = List.unmodifiable(policies);

  /// The typed terms object used when authoring bindings and appearances.
  ///
  /// This is the same `t` object a package can expose to authors. It may be
  /// written by hand or generated later, but it remains a normal Dart object.
  final Vocabulary terms;

  /// The flattened terms that bindings are expected to assign.
  ///
  /// [Design] derives this list from [terms] at construction time. It exists so
  /// validators and policies can inspect the complete vocabulary without knowing
  /// the shape of a project's typed term tree.
  final List<Term> vocabulary;

  /// The named value sets available to resolve vocabulary terms.
  final List<Binding> bindings;

  /// The reusable style declarations in this design.
  final List<Style> styles;

  /// Custom project rules that run after structural validation.
  ///
  /// Policies are ordinary Dart objects. They can inspect this design through a
  /// [PolicyContext] and report diagnostics using their own stable codes.
  final List<Policy> policies;

  /// Returns structural and policy diagnostics for this design.
  ///
  /// Structural validation checks the relationships visible in the manifest:
  ///
  /// * identifier syntax for terms, bindings, assignments, axes, states, and
  ///   styles;
  /// * duplicate term, binding, and style identifiers;
  /// * duplicate assignments inside each binding;
  /// * vocabulary terms missing from a binding;
  /// * style parts, axes, and states that are not declared by the style contract.
  ///
  /// Each [Policy] then receives a [PolicyContext] for project-specific checks:
  ///
  /// ```dart
  /// final diagnostics = design.validate();
  ///
  /// if (diagnostics.any((diagnostic) => diagnostic.severity == .error)) {
  ///   throw StateError('Design is not publishable.');
  /// }
  /// ```
  List<Diagnostic> validate() {
    final diagnostics = <Diagnostic>[
      ..._validateIdentifiers(
        kind: 'term',
        ids: vocabulary.map((term) => term.id),
      ),
      ..._validateIdentifiers(kind: 'binding', ids: bindings.map((b) => b.id)),
      ..._validateIdentifiers(kind: 'style', ids: styles.map((s) => s.id)),
    ];

    for (final binding in bindings) {
      diagnostics.addAll(binding.validate());
      diagnostics.addAll(_validateBindingCompleteness(binding));
    }

    for (final style in styles) {
      diagnostics.addAll(_validateStyle(style));
    }

    final context = _PolicyContext(this, diagnostics);
    for (final policy in policies) {
      policy.evaluate(context);
    }

    return diagnostics;
  }

  List<Diagnostic> _validateBindingCompleteness(Binding binding) {
    final diagnostics = <Diagnostic>[];
    final assigned = {
      for (final assignment in binding.assignments) assignment.term.id.value,
    };

    for (final term in vocabulary) {
      if (assigned.contains(term.id.value)) {
        continue;
      }

      diagnostics.add(
        Diagnostic(
          code: DiagnosticCodes.designMissingBindingValue,
          target: DiagnosticTarget(kind: 'binding', name: binding.id.value),
          message:
              'Binding `${binding.id.value}` does not assign vocabulary term '
              '`${term.id.value}`.',
        ),
      );
    }

    return diagnostics;
  }

  List<Diagnostic> _validateStyle(Style style) {
    final contract = style.contract;
    final diagnostics = <Diagnostic>[];

    if (contract != null) {
      for (final entry in style.parts.entries) {
        if (contract.allowsPart(entry.key)) {
          continue;
        }

        diagnostics.add(
          Diagnostic(
            code: DiagnosticCodes.styleUnknownPart,
            target: DiagnosticTarget(kind: 'style', name: style.id.value),
            message:
                'Style `${style.id.value}` declares part `${entry.key}` that is '
                'not present in its contract.',
          ),
        );
      }

      diagnostics.addAll(
        _validateIdentifiers(
          kind: 'axis',
          ids: contract.axes.map((axis) => axis.id),
        ),
      );
      diagnostics.addAll(
        _validateIdentifiers(
          kind: 'state',
          ids: contract.states.map((declaredState) => declaredState.id),
        ),
      );
    }

    for (final styleCase in style.cases) {
      diagnostics.addAll(_validateCondition(style, contract, styleCase.when));
    }

    return diagnostics;
  }

  List<Diagnostic> _validateCondition(
    Style style,
    Contract? contract,
    Condition condition,
  ) {
    switch (condition) {
      case AxisCondition<Object?>(:final axis):
        return [
          ...axis.id.validate(
            target: DiagnosticTarget(kind: 'axis', name: axis.id.value),
          ),
          if (contract != null && !contract.allowsAxis(axis))
            Diagnostic(
              code: DiagnosticCodes.styleUnknownAxis,
              target: DiagnosticTarget(kind: 'style', name: style.id.value),
              message:
                  'Style `${style.id.value}` uses axis `${axis.id.value}` that '
                  'is not present in its contract.',
            ),
        ];
      case State(:final id):
        return [
          ...id.validate(
            target: DiagnosticTarget(kind: 'state', name: id.value),
          ),
          if (contract != null && !contract.allowsState(condition))
            Diagnostic(
              code: DiagnosticCodes.styleUnknownState,
              target: DiagnosticTarget(kind: 'style', name: style.id.value),
              message:
                  'Style `${style.id.value}` uses state `${id.value}` that is '
                  'not present in its contract.',
            ),
        ];
      case AllCondition(:final conditions):
        return [
          for (final child in conditions)
            ..._validateCondition(style, contract, child),
        ];
      case AnyCondition(:final conditions):
        return [
          for (final child in conditions)
            ..._validateCondition(style, contract, child),
        ];
      case NotCondition(:final condition):
        return _validateCondition(style, contract, condition);
      case Condition():
        return const [];
    }
  }
}

/// A custom validation rule for a [Design].
///
/// Policies are normal Dart objects instead of function factories. That keeps
/// configuration explicit, testable, and easy to share from extension packages:
///
/// ```dart
/// final class NoRawColorPolicy implements Policy {
///   const NoRawColorPolicy();
///
///   @override
///   String get code => 'design.no_raw_color';
///
///   @override
///   void evaluate(PolicyContext context) {
///     // Inspect context.design and call context.report(...).
///   }
/// }
/// ```
abstract interface class Policy {
  /// A stable identifier for this policy.
  ///
  /// Policy implementations may use this as a diagnostic code prefix or as a
  /// configuration key. The core validator does not synthesize diagnostics from
  /// it automatically, because each policy owns its own messages and severity.
  String get code;

  /// Evaluates this policy against [context].
  void evaluate(PolicyContext context);
}

/// A typed term tree that can expose all of its vocabulary terms.
///
/// The public design API accepts `terms: t` so authoring code can keep using a
/// domain-specific object such as `t.color.action.fill`. This protocol is the
/// bridge that lets validation also enumerate those terms:
///
/// ```dart
/// final class AppTerms implements Vocabulary {
///   const AppTerms();
///
///   ColorTerms get color => const ColorTerms();
///   RadiusTerms get radius => const RadiusTerms();
///
///   @override
///   Iterable<Term> get terms => [
///     color.action.fill,
///     radius.control,
///   ];
/// }
/// ```
///
/// Future generators can produce the same ordinary Dart shape. They do not need
/// to introduce a second style language or hidden runtime registry.
abstract interface class Vocabulary {
  /// Every term that belongs to this vocabulary.
  Iterable<Term> get terms;
}

/// The reporting surface passed to [Policy.evaluate].
///
/// A policy context exposes the current [design] and a single [report] method.
/// Policies should report all findings they can discover in one pass instead of
/// throwing at the first violation.
abstract interface class PolicyContext {
  /// The design being evaluated.
  Design get design;

  /// Adds [diagnostic] to the result returned by [Design.validate].
  void report(Diagnostic diagnostic);
}

final class _PolicyContext implements PolicyContext {
  _PolicyContext(this.design, this._diagnostics);

  @override
  final Design design;

  final List<Diagnostic> _diagnostics;

  @override
  void report(Diagnostic diagnostic) {
    _diagnostics.add(diagnostic);
  }
}

List<Diagnostic> _validateIdentifiers({
  required String kind,
  required Iterable<Identifier> ids,
}) {
  final diagnostics = <Diagnostic>[];
  final seen = <String, Identifier>{};
  final seenIgnoringCase = <String, Identifier>{};

  for (final id in ids) {
    final target = DiagnosticTarget(kind: kind, name: id.value);

    diagnostics.addAll(id.validate(target: target));

    final duplicate = seen[id.value];
    if (duplicate != null) {
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCodes.identifierDuplicate,
          target: target,
          message: '$kind `${id.value}` is already defined.',
        ),
      );
    } else {
      seen[id.value] = id;
    }

    final folded = id.value.toLowerCase();
    final caseDuplicate = seenIgnoringCase[folded];
    if (caseDuplicate != null && caseDuplicate.value != id.value) {
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCodes.identifierDuplicateIgnoringCase,
          target: target,
          message:
              '$kind `${id.value}` conflicts with `${caseDuplicate.value}` '
              'when compared case-insensitively.',
        ),
      );
    } else {
      seenIgnoringCase[folded] = id;
    }
  }

  return diagnostics;
}
