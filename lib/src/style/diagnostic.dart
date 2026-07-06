/// Severity for a style-core diagnostic.
enum DiagnosticSeverity { info, warning, error }

/// Stable diagnostic code constants used by Odroe's style core.
abstract final class DiagnosticCodes {
  static const identifierEmpty = 'identifier.empty';
  static const identifierEmptySegment = 'identifier.empty_segment';
  static const identifierInvalidSegment = 'identifier.invalid_segment';
  static const identifierDuplicate = 'identifier.duplicate';
  static const identifierDuplicateIgnoringCase =
      'identifier.duplicate_ignoring_case';
}

/// A structured diagnostic produced by validation or policy code.
final class Diagnostic {
  const Diagnostic({
    required this.code,
    required this.message,
    this.severity = DiagnosticSeverity.error,
    this.target,
  });

  final String code;
  final DiagnosticSeverity severity;
  final DiagnosticTarget? target;
  final String message;

  @override
  String toString() {
    final targetText = target == null ? '' : ' at $target';
    return '[$severity] $code$targetText: $message';
  }
}

/// The design entity a diagnostic points at.
final class DiagnosticTarget {
  const DiagnosticTarget({required this.kind, this.name, this.location});

  final String kind;
  final String? name;
  final DiagnosticLocation? location;

  @override
  String toString() {
    final nameText = name == null ? kind : '$kind `$name`';
    return location == null ? nameText : '$nameText ($location)';
  }
}

/// Optional source location metadata for diagnostics.
final class DiagnosticLocation {
  const DiagnosticLocation({this.source, this.offset, this.line, this.column});

  final String? source;
  final int? offset;
  final int? line;
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
