import 'dart:async';

import 'package:macros/macros.dart';

macro class Odroe implements ClassTypesMacro, ClassDeclarationsMacro, ClassDefinitionMacro {
  const Odroe();

  @override
  FutureOr<void> buildTypesForClass(
      ClassDeclaration clazz, ClassTypeBuilder builder) async {
    // ignore: deprecated_member_use
    final stateless = await builder.resolveIdentifier(
        Uri.parse('package:flutter/widgets.dart'),
        'StatelessWidget'
    );

    

    builder.extendsType(NamedTypeAnnotationCode(name: stateless));
  }

  @override
  FutureOr<void> buildDeclarationsForClass(ClassDeclaration clazz, MemberDeclarationBuilder builder) async {
    final constructor = await defaultConstructorDeclarationOf(clazz, builder);
    final fields = await builder.fieldsOf(clazz);

    // throw fields.first.;
  }

  @override
  FutureOr<void> buildDefinitionForClass(ClassDeclaration clazz, TypeDefinitionBuilder builder) async {
    final constructor = await defaultConstructorDeclarationOf(clazz, builder);
    final demo = await builder.buildConstructor(constructor.identifier);

    for (final param in constructor.namedParameters) {
        if (param.metadata.isNotEmpty) {
          throw param.code.kind;
        }
    }
  }
}

extension on Odroe {
  Future<ConstructorDeclaration> defaultConstructorDeclarationOf(TypeDeclaration type, DeclarationPhaseIntrospector introspector) async {
    final constructors = await introspector.constructorsOf(type);
    return constructors.singleWhere((e) => e.identifier.name.isEmpty);
  }
}
