import 'diagnostic.dart';

final _identifierSegmentPattern = RegExp(r'^[a-z][A-Za-z0-9_]*$');

/// A stable authoring name for a style declaration.
///
/// Identifiers name concepts in the design model, such as
/// `color.action.fill`, `space.control_x`, or `button.tone`. They are not
/// output names. Platform adapters may translate an identifier into a CSS
/// custom property, a generated Dart constant, or another target-specific name,
/// but the identifier remains the stable value used by core validation,
/// diagnostics, and policy code.
///
/// Construction does not validate the string. Invalid identifiers need to be
/// representable so tools can load incomplete design data and report structured
/// diagnostics instead of throwing while reading.
///
/// ```dart
/// const id = Identifier('color.action.fill');
/// final diagnostics = id.validate();
/// ```
extension type const Identifier(String value) {
  /// The dot-separated path segments in [value].
  ///
  /// Empty segments are preserved. For example, `color..action` produces
  /// `['color', '', 'action']`, which lets [validate] report the exact problem.
  List<String> get segments => value.split('.');

  /// Checks whether [value] follows Odroe's identifier syntax.
  ///
  /// Valid identifiers are dot-separated paths whose segments start with a
  /// lowercase letter and then contain only letters, digits, or underscores.
  /// Examples include `color.action.fill`, `color.action.fillHover`, and
  /// `space.control_x`.
  ///
  /// Invalid examples include `Color.Action`, `color..action`,
  /// `color action`, and `color.action-fill`.
  ///
  /// It does not check whether the identifier is declared, duplicated, or valid
  /// in a particular owner scope. Those checks require the object that owns the
  /// identifiers, such as a binding, style, or design manifest.
  ///
  /// The optional `target` argument is copied to each reported
  /// [Diagnostic.target]. When it is omitted, diagnostics point at this
  /// identifier value with a target kind of `identifier`.
  ///
  /// ```dart
  /// final diagnostics = Identifier('Color').validate();
  ///
  /// assert(diagnostics.single.code == DiagnosticCodes.identifierInvalidSegment);
  /// ```
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
