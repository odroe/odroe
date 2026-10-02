import 'package:analyzer/diagnostic/diagnostic.dart';

/// Reads the same diagnostic name across the supported analyzer generations.
String diagnosticCodeName(Diagnostic diagnostic) {
  // analyzer 8.4 has no lowerCaseName getter; name is shared by both APIs.
  // ignore: deprecated_member_use
  return diagnostic.diagnosticCode.name.toLowerCase();
}
