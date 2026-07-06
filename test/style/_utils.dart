import 'package:odroe/style.dart';
import 'package:test/test.dart';

Matcher containsDiagnosticCode(String code) {
  return contains(
    isA<Diagnostic>().having((diagnostic) => diagnostic.code, 'code', code),
  );
}
