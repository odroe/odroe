import 'diagnostic.dart';

final _identifierSegmentPattern = RegExp(r'^[a-z][A-Za-z0-9_]*$');

/// A stable dot-separated id for a design entity.
extension type const Identifier(String value) {
  List<String> get segments => value.split('.');

  List<Diagnostic> validate({DiagnosticTarget? target}) {
    final diagnosticTarget =
        target ?? DiagnosticTarget(kind: 'identifier', name: value);

    if (value.isEmpty) {
      return [
        Diagnostic(
          code: DiagnosticCodes.identifierEmpty,
          target: diagnosticTarget,
          message: 'Identifier must not be empty.',
        ),
      ];
    }

    final diagnostics = <Diagnostic>[];
    final segments = this.segments;

    for (var index = 0; index < segments.length; index += 1) {
      final segment = segments[index];

      if (segment.isEmpty) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCodes.identifierEmptySegment,
            target: diagnosticTarget,
            message: 'Identifier segment ${index + 1} must not be empty.',
          ),
        );
        continue;
      }

      if (!_identifierSegmentPattern.hasMatch(segment)) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCodes.identifierInvalidSegment,
            target: diagnosticTarget,
            message:
                'Identifier segment `$segment` must start with a lowercase '
                'letter and contain only letters, digits, or underscores.',
          ),
        );
      }
    }

    return diagnostics;
  }
}
