import 'package:odroe/style.dart';
import 'package:test/test.dart';

Matcher containsDiagnostic({
  required String code,
  String? targetKind,
  String? targetName,
}) {
  var matcher = isA<Diagnostic>().having(
    (diagnostic) => diagnostic.code,
    'code',
    code,
  );

  if (targetKind != null) {
    matcher = matcher.having(
      (diagnostic) => diagnostic.target?.kind,
      'target.kind',
      targetKind,
    );
  }

  if (targetName != null) {
    matcher = matcher.having(
      (diagnostic) => diagnostic.target?.name,
      'target.name',
      targetName,
    );
  }

  return contains(matcher);
}
