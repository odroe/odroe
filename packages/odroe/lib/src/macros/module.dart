import 'dart:async';

import 'package:macros/macros.dart';

macro

// Demo

class Module implements  LibraryTypesMacro {
  const Module(this.providers);

  final TypeAnnotation providers;

  @override
  FutureOr<void> buildDefinitionForClass(
      ClassDeclaration clazz, TypeDefinitionBuilder builder) async {
    // ignore: deprecated_member_use
    // final id = await builder.resolveIdentifier(
    //     clazz.library.uri.resolve('../app.service.dart'), type);

    // throw DiagnosticException(Diagnostic(
    //   DiagnosticMessage('${clazz.library.uri.resolve('../app.service.dart')}', target: clazz.asDiagnosticTarget),
    //   Severity.error,
    // ));
  }

  @override
  FutureOr<void> buildTypesForLibrary(Library library, TypeBuilder builder) {

  }
}
