/// The default importance of a diagnostic.
///
/// Severity is presentation and policy guidance, not control flow. Validators
/// still return every diagnostic they find, and callers decide whether a
/// warning blocks their workflow.
enum DiagnosticSeverity {
  /// Extra information that does not describe invalid style data.
  info,

  /// A problem that should be reviewed before publishing the style data.
  warning,

  /// A problem that normally prevents the declaration from being used.
  error,
}

/// Machine-readable identifiers for style diagnostics.
///
/// Code strings are part of the public contract for validation output. They are
/// stable handles for tests, editors, and build tooling. Messages can be
/// rewritten for clarity without changing the corresponding code.
///
/// Codes are namespaced by the model area that reports them, such as
/// `identifier`, and use lower snake case after the dot.
///
/// ```dart
/// final diagnostics = Identifier('color..action').validate();
///
/// if (diagnostics.any(
///   (diagnostic) => diagnostic.code == DiagnosticCodes.identifierEmptySegment,
/// )) {
///   // Offer an editor quick fix.
/// }
/// ```
abstract final class DiagnosticCodes {
  /// A binding assigns the same term more than once.
  ///
  /// A binding is allowed to contain many assignments, but each term should be
  /// assigned at most once in that binding. Later style resolution can then
  /// choose a binding without needing declaration-order conflict rules inside
  /// the binding itself.
  static const bindingDuplicateAssignment = 'binding.duplicate_assignment';

  /// A binding assigns terms whose identifiers differ only by letter case.
  ///
  /// This protects bindings from declarations that would collapse to the same
  /// key in case-insensitive tooling or generated output.
  static const bindingDuplicateAssignmentIgnoringCase =
      'binding.duplicate_assignment_ignoring_case';

  /// A binding does not assign a term declared by the design vocabulary.
  ///
  /// Design validation reports this when a [Design] knows the complete vocabulary
  /// and can compare every [Binding] against it. A binding can still be validated
  /// on its own without reporting this code, because local binding validation
  /// does not know which terms are required.
  static const designMissingBindingValue = 'design.missing_binding_value';

  /// A binding assigns a term outside the design vocabulary.
  ///
  /// Design validation reports this when a [Binding] contains an assignment for
  /// a foreign or misspelled [Term]. Keeping this at the design layer lets
  /// bindings stay reusable while still preventing complete-but-invalid token
  /// sets from passing manifest validation.
  static const designUnknownBindingValue = 'design.unknown_binding_value';

  /// A binding assigns a value that does not match its vocabulary term type.
  ///
  /// Design validation reports this when an assignment has the same identifier
  /// as a vocabulary [Term], but the authored value is not accepted by that term.
  /// This catches declarations that bypass the typed term object with another
  /// term using the same identifier and an incompatible type argument.
  static const designInvalidBindingValueType =
      'design.invalid_binding_value_type';

  /// An empty [Identifier.value].
  static const identifierEmpty = 'identifier.empty';

  /// An [Identifier] containing an empty segment.
  ///
  /// For example, `color..action` contains an empty segment between the two
  /// dots.
  static const identifierEmptySegment = 'identifier.empty_segment';

  /// An [Identifier] segment that is not a Dart-friendly path segment.
  static const identifierInvalidSegment = 'identifier.invalid_segment';

  /// An identifier value repeated in one owner scope.
  ///
  /// This code is for validators that compare multiple declarations, such as a
  /// future design manifest or binding validator. [Identifier.validate] does
  /// not report this code because it only sees one identifier.
  static const identifierDuplicate = 'identifier.duplicate';

  /// Identifier values that differ only by letter case in one owner scope.
  ///
  /// This code is reserved for validators that compare declarations in a shared
  /// namespace. It is not a lexical error for a single [Identifier].
  static const identifierDuplicateIgnoringCase =
      'identifier.duplicate_ignoring_case';

  /// A style property references a term the selected binding does not assign.
  ///
  /// Resolution reports this when the final merged appearance still contains a
  /// [Property.term] reference, but the selected [Binding] has no assignment for
  /// that term. Declarations remain lazy; this code appears only when a style is
  /// resolved with a concrete binding.
  static const resolutionUnresolvedTerm = 'resolution.unresolved_term';

  /// A binding assignment cannot satisfy the type expected by a style property.
  ///
  /// Resolution reports this when the selected [Binding] contains the requested
  /// term identifier but the stored value cannot be used by the term referenced
  /// from the resolved property.
  static const resolutionInvalidTermValueType =
      'resolution.invalid_term_value_type';

  /// A condition cannot be evaluated by the core resolver.
  ///
  /// Resolution reports this for custom [Condition] subclasses that are outside
  /// the current core condition model. Platform adapters or extension packages
  /// can evaluate their own condition types before calling the core resolver.
  static const resolutionUnsupportedCondition =
      'resolution.unsupported_condition';

  /// A style declares a part that is not present in its contract.
  ///
  /// Contract validation is owned by the style because parts are only meaningful
  /// through the style's part type.
  static const styleUnknownPart = 'style.unknown_part';

  /// A style appearance references a term outside the design vocabulary.
  ///
  /// Design validation reports this when a [Property.term] inside a style root,
  /// part, or case appearance points at a foreign or misspelled [Term]. The
  /// style may still be structurally valid, but it cannot be resolved from the
  /// validated bindings unless every referenced term belongs to the vocabulary.
  static const styleUnknownTerm = 'style.unknown_term';

  /// A style appearance references a term with the wrong value type.
  ///
  /// Design validation reports this when a style term reference has the same
  /// identifier as a vocabulary [Term], but its type argument does not match the
  /// vocabulary term. This protects resolvers from reading a valid binding value
  /// through a style property that expects a different value type.
  static const styleInvalidTermType = 'style.invalid_term_type';

  /// A style case uses an axis that is not present in its contract.
  static const styleUnknownAxis = 'style.unknown_axis';

  /// A style case uses an axis value that does not match its contract axis type.
  ///
  /// Design validation reports this when a condition uses an [Axis] with the
  /// same identifier as a contract axis but with an incompatible type argument
  /// or value.
  static const styleInvalidAxisValueType = 'style.invalid_axis_value_type';

  /// A style case uses a state that is not present in its contract.
  static const styleUnknownState = 'style.unknown_state';
}

/// A non-throwing validation result for style declarations.
///
/// Style validation reports diagnostics instead of throwing so authoring tools
/// can show every problem in one pass. A diagnostic describes the
/// platform-neutral style model, not any projected CSS, Flutter, DOM, or
/// platform-specific output.
///
/// A diagnostic has two audiences. Tools should use [code], [severity], and
/// [target] for programmatic handling. People should read [message], whose
/// wording can improve over time without changing the meaning of [code].
///
/// ```dart
/// for (final diagnostic in Identifier('Color.Action').validate()) {
///   print('${diagnostic.code}: ${diagnostic.message}');
/// }
/// ```
final class Diagnostic {
  /// Creates a diagnostic with a stable [code] and display [message].
  ///
  /// The [code] should remain stable across releases. The [message] should be a
  /// complete sentence that names the problem in style-core terms. Diagnostics
  /// default to [DiagnosticSeverity.error] because structural style problems
  /// should be treated as blocking unless the producer deliberately reports a
  /// softer severity.
  const Diagnostic({
    required this.code,
    required this.message,
    this.severity = DiagnosticSeverity.error,
    this.target,
  });

  /// The stable identifier for the problem.
  ///
  /// Prefer values from [DiagnosticCodes]. Consumers should not parse
  /// [message] when this value is sufficient.
  final String code;

  /// The default importance of the problem.
  ///
  /// Severity is advisory. A caller can still reject a design that reports only
  /// warnings, or allow a design that reports errors, depending on the workflow.
  final DiagnosticSeverity severity;

  /// The declaration or source position associated with the problem.
  ///
  /// A diagnostic can omit the target when it describes a package-level problem
  /// or when the producer does not have enough context to identify an owner.
  final DiagnosticTarget? target;

  /// A human-readable explanation of the problem.
  ///
  /// Messages are written for display and may change as wording improves. Use
  /// [code] for stable matching.
  final String message;

  @override
  String toString() {
    final targetText = target == null ? '' : ' at $target';
    return '[$severity] $code$targetText: $message';
  }
}

/// The declaration associated with a diagnostic.
///
/// A target should point to the style declaration that caused the problem.
/// Platform packages can translate the model later, but core diagnostics should
/// not target CSS custom properties, Flutter widgets, DOM nodes, or generated
/// output names.
///
/// ```dart
/// const target = DiagnosticTarget(
///   kind: 'assignment',
///   name: 'color.action.fill',
/// );
/// ```
final class DiagnosticTarget {
  /// Creates a target for a declaration or source location.
  ///
  /// A useful target should normally provide [name], [location], or both. The
  /// [kind] should be a stable lower-case noun such as `identifier`, `binding`,
  /// `style`, or `policy`.
  const DiagnosticTarget({required this.kind, this.name, this.location});

  /// The category of declaration being reported.
  final String kind;

  /// The user-authored name of the reported object.
  ///
  /// For named declarations this is usually an [Identifier.value]. The name is
  /// optional because some diagnostics point at unnamed structures or at source
  /// text that could not be read into a complete object.
  final String? name;

  /// The source location of the reported object, when known.
  final DiagnosticLocation? location;

  @override
  String toString() {
    final nameText = name == null ? kind : '$kind `$name`';
    return location == null ? nameText : '$nameText ($location)';
  }
}

/// Source coordinates for a diagnostic.
///
/// Locations are optional because style declarations can be constructed
/// directly in Dart, generated by tools, or loaded from files that provide
/// different amounts of source information.
///
/// ```dart
/// const location = DiagnosticLocation(
///   source: 'tokens.dart',
///   line: 12,
///   column: 8,
/// );
/// ```
final class DiagnosticLocation {
  /// Creates source coordinates using the information available to the producer.
  ///
  /// [offset] is a zero-based UTF-16 code-unit offset into [source]. [line] and
  /// [column] are one-based so they can be displayed directly in editor and
  /// command-line diagnostics.
  const DiagnosticLocation({this.source, this.offset, this.line, this.column});

  /// The file path, URI, or tool-defined source name.
  final String? source;

  /// The zero-based UTF-16 code-unit offset in [source].
  ///
  /// Leave this unset when the source is not text, or when the producer only
  /// knows line and column information.
  final int? offset;

  /// The one-based line number in [source].
  final int? line;

  /// The one-based column number in [source].
  final int? column;

  @override
  String toString() {
    final parts = <String>[
      ?source,
      if (line != null) 'line $line',
      if (column != null) 'column $column',
      if (offset != null) 'offset $offset',
    ];

    return parts.join(', ');
  }
}
