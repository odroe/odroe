import 'dart:async';

import 'package:macros/macros.dart';

macro class Setup implements FunctionTypesMacro, FunctionDefinitionMacro, FunctionDeclarationsMacro {
  const Setup();

  @override
  FutureOr<void> buildTypesForFunction(
      FunctionDeclaration function, TypeBuilder builder) {
  }
  
  @override
  FutureOr<void> buildDefinitionForFunction(FunctionDeclaration function, FunctionDefinitionBuilder builder) async {
    // FunctionBodyCode.fromParts(function.returnType.code.parts);
    // builder.augment(
    //   FunctionBodyCode.fromString('''
    //     => print('Setting up ${function.identifier.name}');
    //   '''),
    // );
    builder.augment(
      FunctionBodyCode.fromParts(function.returnType.code.parts)
    );
  }
  
  @override
  FutureOr<void> buildDeclarationsForFunction(FunctionDeclaration function, DeclarationBuilder builder) {
    // builder.declareInLibrary(function.metadata.first);
  }
}
