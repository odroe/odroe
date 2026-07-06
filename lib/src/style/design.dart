import 'axis.dart';
import 'appearance.dart';
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
/// typed vocabulary object a system authors against, the bindings that give its
/// terms values, the styles that consume appearances and contracts, and the
/// custom policies a project wants to enforce.
///
/// ```dart
/// const t = AppTerms();
///
/// final design = Design(
///   vocabulary: t,
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
final class Design<V extends Vocabulary> {
  /// Creates a style design manifest.
  ///
  /// All collections are copied into immutable lists. Mutating a source list
  /// after construction will not change the design being validated.
  Design({
    required this.vocabulary,
    Iterable<Binding> bindings = const [],
    Iterable<Style> styles = const [],
    Iterable<Policy> policies = const [],
  }) : terms = List.unmodifiable(vocabulary.terms),
       bindings = List.unmodifiable(bindings),
       styles = List.unmodifiable(styles),
       policies = List.unmodifiable(policies);

  /// The typed vocabulary object used when authoring bindings and appearances.
  ///
  /// This is the same `t` object a package can expose to authors. It may be
  /// written by hand or generated later, but it remains a normal Dart object.
  final V vocabulary;

  /// The flattened terms that bindings are expected to assign.
  ///
  /// [Design] derives this list from [vocabulary] at construction time. It
  /// exists so validators and policies can inspect the complete vocabulary
  /// without knowing the shape of a project's typed term tree.
  final List<Term> terms;

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
  /// * binding assignments that do not belong to the vocabulary;
  /// * binding assignments whose values do not match the vocabulary term type;
  /// * style appearance term references that do not belong to the vocabulary;
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
    final vocabularyById = _termsById(terms);
    final diagnostics = <Diagnostic>[
      ..._validateIdentifiers(kind: 'term', ids: terms.map((term) => term.id)),
      ..._validateIdentifiers(kind: 'binding', ids: bindings.map((b) => b.id)),
      ..._validateIdentifiers(kind: 'style', ids: styles.map((s) => s.id)),
    ];

    for (final binding in bindings) {
      diagnostics.addAll(binding.validate());
      diagnostics.addAll(_validateBindingVocabulary(binding, vocabularyById));
    }

    for (final style in styles) {
      diagnostics.addAll(_validateStyle(style, vocabularyById));
    }

    final context = _PolicyContext(this, diagnostics);
    for (final policy in policies) {
      policy.evaluate(context);
    }

    return diagnostics;
  }

  List<Diagnostic> _validateBindingVocabulary(
    Binding binding,
    Map<String, Term> vocabularyById,
  ) {
    final diagnostics = <Diagnostic>[];
    final assigned = <String>{};

    for (final assignment in binding.assignments) {
      final termId = assignment.term.id.value;
      final vocabularyTerm = vocabularyById[termId];
      if (vocabularyTerm == null) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCodes.designUnknownBindingValue,
            target: DiagnosticTarget(kind: 'assignment', name: termId),
            message:
                'Binding `${binding.id.value}` assigns term `$termId`, but '
                'this term is not declared by the design vocabulary.',
          ),
        );

        continue;
      }

      if (!vocabularyTerm.acceptsValue(assignment.value)) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCodes.designInvalidBindingValueType,
            target: DiagnosticTarget(kind: 'assignment', name: termId),
            message:
                'Binding `${binding.id.value}` assigns a '
                '${assignment.value.runtimeType} value to term `$termId`, but '
                'the design vocabulary declares that term as '
                '${vocabularyTerm.valueType}.',
          ),
        );

        continue;
      }

      assigned.add(termId);
    }

    for (final term in terms) {
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

  List<Diagnostic> _validateStyle(
    Style style,
    Map<String, Term> vocabularyById,
  ) {
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

    diagnostics.addAll(
      _validateAppearanceVocabulary(style, style.root, vocabularyById),
    );
    for (final appearance in style.parts.values) {
      diagnostics.addAll(
        _validateAppearanceVocabulary(style, appearance, vocabularyById),
      );
    }
    for (final styleCase in style.cases) {
      diagnostics.addAll(_validateCondition(style, contract, styleCase.when));
      diagnostics.addAll(
        _validateAppearanceVocabulary(
          style,
          styleCase.appearance,
          vocabularyById,
        ),
      );
    }

    return diagnostics;
  }

  List<Diagnostic> _validateAppearanceVocabulary(
    Style style,
    Appearance appearance,
    Map<String, Term> vocabularyById,
  ) {
    final diagnostics = <Diagnostic>[];

    for (final term in _appearanceTerms(appearance)) {
      final termId = term.id.value;
      final vocabularyTerm = vocabularyById[termId];
      if (vocabularyTerm == null) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCodes.styleUnknownTerm,
            target: DiagnosticTarget(kind: 'term', name: termId),
            message:
                'Style `${style.id.value}` references term `$termId`, but this '
                'term is not declared by the design vocabulary.',
          ),
        );

        continue;
      }

      if (!vocabularyTerm.acceptsContract(term)) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCodes.styleInvalidTermType,
            target: DiagnosticTarget(kind: 'term', name: termId),
            message:
                'Style `${style.id.value}` references term `$termId` as '
                '${term.valueType}, but the design vocabulary declares that '
                'term as ${vocabularyTerm.valueType}.',
          ),
        );
      }
    }

    return diagnostics;
  }

  List<Diagnostic> _validateCondition(
    Style style,
    Contract? contract,
    Condition condition,
  ) {
    switch (condition) {
      case AxisCondition<Object?>(:final axis, :final value):
        final declaredAxis = contract?.axisNamed(axis.id);
        return [
          ...axis.id.validate(
            target: DiagnosticTarget(kind: 'axis', name: axis.id.value),
          ),
          if (contract != null && declaredAxis == null)
            Diagnostic(
              code: DiagnosticCodes.styleUnknownAxis,
              target: DiagnosticTarget(kind: 'style', name: style.id.value),
              message:
                  'Style `${style.id.value}` uses axis `${axis.id.value}` that '
                  'is not present in its contract.',
            ),
          if (declaredAxis != null &&
              (!declaredAxis.acceptsContract(axis) ||
                  !declaredAxis.acceptsValue(value)))
            Diagnostic(
              code: DiagnosticCodes.styleInvalidAxisValueType,
              target: DiagnosticTarget(kind: 'axis', name: axis.id.value),
              message:
                  'Style `${style.id.value}` uses a ${value.runtimeType} value '
                  'for axis `${axis.id.value}`, but its contract declares that '
                  'axis as ${declaredAxis.valueType}.',
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

Map<String, Term> _termsById(Iterable<Term> terms) {
  final termsById = <String, Term>{};

  for (final term in terms) {
    termsById.putIfAbsent(term.id.value, () => term);
  }

  return termsById;
}

Iterable<Term> _appearanceTerms(Appearance appearance) sync* {
  final surface = appearance.surface;
  if (surface != null) {
    yield* _propertyTerms(surface.fill);
    yield* _propertyTerms(surface.stroke);
    yield* _propertyTerms(surface.radius);
    yield* _propertyTerms(surface.elevation);
  }

  final content = appearance.content;
  if (content != null) {
    yield* _propertyTerms(content.color);
    yield* _propertyTerms(content.text);
    yield* _propertyTerms(content.icon);
    yield* _propertyTerms(content.opacity);
  }

  final metrics = appearance.metrics;
  if (metrics != null) {
    yield* _insetTerms(metrics.padding);
    yield* _propertyTerms(metrics.gap);
    yield* _propertyTerms(metrics.width);
    yield* _propertyTerms(metrics.height);
    yield* _propertyTerms(metrics.minWidth);
    yield* _propertyTerms(metrics.minHeight);
    yield* _propertyTerms(metrics.maxWidth);
    yield* _propertyTerms(metrics.maxHeight);
  }
}

Iterable<Term> _insetTerms(Insets? insets) sync* {
  if (insets == null) {
    return;
  }

  yield* _propertyTerms(insets.top);
  yield* _propertyTerms(insets.right);
  yield* _propertyTerms(insets.bottom);
  yield* _propertyTerms(insets.left);
}

Iterable<Term> _propertyTerms(Property<Object?>? property) sync* {
  switch (property) {
    case TermProperty<Object?>(:final term):
      yield term;
    case LiteralProperty<Object?>() || null:
      return;
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

/// A typed vocabulary tree that can expose its terms.
///
/// The public design API accepts `vocabulary: t` so authoring code can keep
/// using a domain-specific object such as `t.color.action.fill`. This protocol is
/// the bridge that lets validation also enumerate those terms:
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
