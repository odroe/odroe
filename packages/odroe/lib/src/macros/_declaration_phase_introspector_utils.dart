import 'package:macros/macros.dart';

extension DeclarationPhaseIntrospectorUtils on DeclarationPhaseIntrospector {
  Future<ConstructorDeclaration> constructorOf(
      TypeDeclaration type, String name) async {
    final constructors = await constructorsOf(type);
    final foundConstructor =
        constructors.where((e) => e.identifier.name == name).firstOrNull;

    if (foundConstructor == null) {
      throw DiagnosticException(Diagnostic(
        DiagnosticMessage(
          'No `${type.identifier.name}.${name}` constructor/factory found.',
          target: type.asDiagnosticTarget,
        ),
        Severity.error,
      ));
    }

    return foundConstructor;
  }
}
