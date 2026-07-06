/// The default importance of a [Diagnostic].
///
/// Severity is presentation and policy guidance, not control flow. Validators
/// still return every diagnostic they find, and callers decide whether a
/// warning blocks their workflow.
enum DiagnosticSeverity {
  /// Context that does not indicate invalid style data.
  info,

  /// A problem that should be reviewed by the author.
  warning,

  /// A problem that normally prevents the style data from being used.
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
abstract final class DiagnosticCodes {
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
}

/// A non-throwing validation result for style-core data.
///
/// Style validation reports diagnostics instead of throwing so authoring tools
/// can show every problem in one pass. A diagnostic describes the
/// platform-neutral style model, not any projected CSS, Flutter, DOM, or
/// platform-specific output.
///
/// A diagnostic has two audiences. Tools should use [code], [severity], and
/// [target] for programmatic handling. People should read [message], whose
/// wording can improve over time without changing the meaning of [code].
final class Diagnostic {
  /// Creates a diagnostic with a stable code and a display message.
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

  /// The stable identifier for the problem that was found.
  ///
  /// Prefer values from [DiagnosticCodes]. Consumers should not parse
  /// [message] when this value is sufficient.
  final String code;

  /// The default importance of this diagnostic.
  ///
  /// Severity is advisory. A caller can still reject a design that reports only
  /// warnings, or allow a design that reports errors, depending on the workflow.
  final DiagnosticSeverity severity;

  /// The model object or source position associated with the problem.
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

/// The style-core object or declaration associated with a diagnostic.
///
/// A target should point to the style declaration that caused the problem.
/// Platform packages can translate the model later, but core diagnostics should
/// not target CSS custom properties, Flutter widgets, DOM nodes, or generated
/// output names.
final class DiagnosticTarget {
  /// Creates a target for a model object or source location.
  ///
  /// A useful target should normally provide [name], [location], or both. The
  /// [kind] should be a stable lower-case noun such as `identifier`, `binding`,
  /// `style`, or `policy`.
  const DiagnosticTarget({required this.kind, this.name, this.location});

  /// The category of style-core object being reported.
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

/// Source coordinates for a diagnostic target.
///
/// Locations are optional because style declarations can be constructed
/// directly in Dart, generated by tools, or loaded from files that provide
/// different amounts of source information.
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
      if (source != null) source!,
      if (line != null) 'line $line',
      if (column != null) 'column $column',
      if (offset != null) 'offset $offset',
    ];

    return parts.join(', ');
  }
}
