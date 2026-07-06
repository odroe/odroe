import 'diagnostic.dart';
import 'identifier.dart';

/// Validates a group of identifiers and reports exact or case-insensitive
/// duplicates in addition to per-identifier format diagnostics.
///
/// This is package-internal validation support for future design manifests and
/// policy contexts. It is intentionally not exported from `package:odroe/style.dart`.
List<Diagnostic> validateIdentifierSet(Iterable<Identifier> identifiers) {
  final diagnostics = <Diagnostic>[];
  final seen = <String, Identifier>{};
  final seenIgnoringCase = <String, Identifier>{};

  for (final identifier in identifiers) {
    final target = DiagnosticTarget(kind: 'identifier', name: identifier.value);

    diagnostics.addAll(identifier.validate(target: target));

    final duplicate = seen[identifier.value];
    if (duplicate != null) {
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCodes.identifierDuplicate,
          target: target,
          message: 'Identifier `${identifier.value}` is already defined.',
        ),
      );
    } else {
      seen[identifier.value] = identifier;
    }

    final folded = identifier.value.toLowerCase();
    final caseDuplicate = seenIgnoringCase[folded];
    if (caseDuplicate != null && caseDuplicate.value != identifier.value) {
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCodes.identifierDuplicateIgnoringCase,
          target: target,
          message:
              'Identifier `${identifier.value}` conflicts with '
              '`${caseDuplicate.value}` when compared case-insensitively.',
        ),
      );
    } else {
      seenIgnoringCase[folded] = identifier;
    }
  }

  return diagnostics;
}
