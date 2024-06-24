import 'dart:async';

import 'package:macros/macros.dart';

macro class Setup implements FunctionDeclarationsMacro, FunctionDefinitionMacro {
  const Setup();

  @override
  FutureOr<void> buildDeclarationsForFunction(FunctionDeclaration function, DeclarationBuilder builder) async {
    // throw builder.res;
  }
  
  @override
  FutureOr<void> buildDefinitionForFunction(FunctionDeclaration function, FunctionDefinitionBuilder builder) {
    builder.augment;
  }
}
