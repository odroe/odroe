import 'dart:async';

import 'package:macros/macros.dart';

macro class Component implements FunctionTypesMacro, FunctionDefinitionMacro {
  const Component();

  @override
  FutureOr<void> buildDefinitionForFunction(FunctionDeclaration function, FunctionDefinitionBuilder builder) async {
    // builder.
    builder.augment(FunctionBodyCode.fromString('=> 1;'));
  }

  
  @override
  FutureOr<void> buildTypesForFunction(FunctionDeclaration function, TypeBuilder builder) {
    builder.declareType('A', DeclarationCode.fromString('class A {}'));
    builder.declareType('B', DeclarationCode.fromString('class B {}'));
    
  }
}
