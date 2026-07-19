// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import 'model.dart';

final class ServerFunctionScanner {
  ServerFunctionScanner(this.projectRoot);

  final Directory projectRoot;

  void scan(RouteNode node, File file, List<FileRouteDiagnostic> diagnostics) {
    final result = parseString(
      content: file.readAsStringSync(),
      path: file.path,
      throwIfDiagnostics: false,
    );
    for (final error in result.errors) {
      _error(diagnostics, file.path, error.message);
    }
    if (result.errors.isNotEmpty) return;

    for (final directive
        in result.unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == null) continue;
      node.serverImports.add(
        ServerImport(uri: uri, prefix: directive.prefix?.name),
      );
    }

    var exportsRoute = false;
    for (final declaration
        in result.unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      for (final variable in declaration.variables.variables) {
        final name = variable.name.lexeme;
        if (name == 'route') {
          exportsRoute = true;
          final initializer = variable.initializer;
          final arguments = switch (initializer) {
            InstanceCreationExpression() => initializer.argumentList,
            MethodInvocation() => initializer.argumentList,
            _ => null,
          };
          node.serverTerminal =
              arguments?.arguments.whereType<NamedExpression>().any(
                (argument) => argument.name.label.name == 'handlers',
              ) ??
              false;
          continue;
        }
        final initializer = variable.initializer;
        final (typeName, typeArguments, argumentList) = switch (initializer) {
          InstanceCreationExpression() => (
            initializer.constructorName.type.name.lexeme,
            initializer.constructorName.type.typeArguments,
            initializer.argumentList,
          ),
          MethodInvocation() => (
            initializer.methodName.name,
            initializer.typeArguments,
            initializer.argumentList,
          ),
          _ => (null, null, null),
        };
        if (typeName != 'ServerFunction') continue;
        final arguments = typeArguments?.arguments;
        if (arguments == null || arguments.length != 2) {
          _error(
            diagnostics,
            file.path,
            'ServerFunction "$name" must declare input and output types.',
          );
          continue;
        }
        if (name.startsWith('_')) {
          _error(
            diagnostics,
            file.path,
            'ServerFunction "$name" must be public so generated code can bind it.',
          );
          continue;
        }
        final input = arguments[0].toSource();
        final output = arguments[1];
        final unsharedTypes = <String>{};
        for (final type in arguments) {
          type.accept(_ClientTypeVisitor(unsharedTypes));
        }
        if (unsharedTypes.isNotEmpty) {
          _error(
            diagnostics,
            file.path,
            'ServerFunction "$name" uses client-visible type(s) '
            '${unsharedTypes.join(', ')} without an import prefix. Put domain '
            'types in a shared library and import it with a prefix.',
          );
          continue;
        }
        final streamType =
            output is NamedType &&
                output.name.lexeme == 'Stream' &&
                output.typeArguments?.arguments.length == 1
            ? output.typeArguments!.arguments.single.toSource()
            : null;
        final inputIssue = _wireTypeIssue(input, input: true);
        final outputIssue = _wireTypeIssue(
          streamType ?? output.toSource(),
          input: false,
        );
        if (inputIssue != null || outputIssue != null) {
          _error(
            diagnostics,
            file.path,
            'ServerFunction "$name" has an unsupported wire type: '
            '${inputIssue ?? outputIssue}',
          );
          continue;
        }
        var method = 'HttpMethod.post';
        for (final argument
            in argumentList!.arguments.whereType<NamedExpression>()) {
          if (argument.name.label.name != 'method') continue;
          final source = argument.expression.toSource();
          if (!RegExp(
            r'^(?:[A-Za-z_]\w*\.)?HttpMethod\.[a-z]+$',
          ).hasMatch(source)) {
            _error(
              diagnostics,
              file.path,
              'ServerFunction "$name" method must be a HttpMethod value.',
            );
          } else {
            method = 'HttpMethod.${source.split('.').last}';
          }
        }
        node.functions.add(
          ServerFunctionDeclaration(
            name: name,
            inputType: input,
            outputType: output.toSource(),
            streamType: streamType,
            method: method,
          ),
        );
      }
    }
    if (!exportsRoute) {
      _error(
        diagnostics,
        file.path,
        'File must export a top-level variable named route.',
      );
    }
  }

  String _relative(String path) => p.relative(path, from: projectRoot.path);

  void _error(
    List<FileRouteDiagnostic> diagnostics,
    String path,
    String message,
  ) {
    diagnostics.add(
      FileRouteDiagnostic(
        severity: FileRouteDiagnosticSeverity.error,
        path: _relative(path),
        message: message,
      ),
    );
  }
}

String? _wireTypeIssue(String source, {required bool input}) {
  late final _WireType type;
  try {
    type = _WireType.parse(source);
  } on FormatException catch (error) {
    return error.message;
  }
  return _validateWireType(type, input: input, topLevel: true);
}

String? _validateWireType(
  _WireType type, {
  required bool input,
  required bool topLevel,
}) {
  final base = type.base;
  if (base.startsWith('(') ||
      base.contains(' Function(') ||
      base.startsWith('Function(')) {
    return '${type.source} is not JSON serializable';
  }
  if (base == 'Future' || base == 'Stream' || base == 'Never') {
    return '${type.source} is not a value wire type';
  }
  if (base == 'void') {
    return !input && topLevel ? null : 'void is only valid as output';
  }
  if (base == 'NoServerInput') {
    return input && topLevel
        ? null
        : 'NoServerInput is only valid as direct input';
  }
  if (base == 'ServerResponse') {
    return !input && topLevel
        ? null
        : 'ServerResponse is only valid as direct output';
  }
  if (const <String>{
    'ByteBuffer',
    'ByteData',
    'Float32List',
    'Float64List',
    'Int8List',
    'Int16List',
    'Int32List',
    'Int64List',
    'Uint16List',
    'Uint32List',
    'Uint64List',
  }.contains(base)) {
    return '$base has no built-in serializer';
  }
  if (base == 'Map') {
    if (type.arguments.length != 2 || type.arguments.first.source != 'String') {
      return 'Map wire types must be Map<String, T>';
    }
    return _validateWireType(type.arguments[1], input: input, topLevel: false);
  }
  if (base == 'List' || base == 'Set' || base == 'Iterable') {
    if (type.arguments.length != 1) {
      return '$base wire types require one type argument';
    }
    return _validateWireType(
      type.arguments.single,
      input: input,
      topLevel: false,
    );
  }
  return null;
}

String? wireDecoder(String source, String value) {
  final type = _WireType.parse(source);
  final base = type.base;
  if (base != 'List' && base != 'Set' && base != 'Iterable' && base != 'Map') {
    return null;
  }
  return _decodeWireValue(type, value);
}

String _decodeWireValue(_WireType type, String value) {
  final decoded = switch (type.base) {
    'List' =>
      '($value as List).map((item) => '
          '${_decodeWireValue(type.arguments.single, 'item')})'
          '.toList(growable: false)',
    'Set' =>
      '($value as List).map((item) => '
          '${_decodeWireValue(type.arguments.single, 'item')}).toSet()',
    'Iterable' =>
      '($value as List).map((item) => '
          '${_decodeWireValue(type.arguments.single, 'item')})',
    'Map' =>
      '<String, ${type.arguments[1].source}>{'
          'for (final entry in ($value as Map).entries) '
          'entry.key as String: '
          '${_decodeWireValue(type.arguments[1], 'entry.value')}}',
    'dynamic' || 'Object' => value,
    _ => '$value as ${type.nonNullableSource}',
  };
  return type.nullable ? '($value == null ? null : $decoded)' : decoded;
}

final class _WireType {
  const _WireType({
    required this.base,
    required this.arguments,
    required this.nullable,
  });

  factory _WireType.parse(String source) {
    var value = source.trim();
    if (value.isEmpty) throw const FormatException('empty type');
    final nullable = value.endsWith('?');
    if (nullable) value = value.substring(0, value.length - 1).trimRight();
    final open = value.indexOf('<');
    if (open < 0) {
      return _WireType(
        base: value,
        arguments: const <_WireType>[],
        nullable: nullable,
      );
    }
    if (!value.endsWith('>')) {
      throw FormatException('Malformed generic wire type $source');
    }
    final base = value.substring(0, open).trim();
    final body = value.substring(open + 1, value.length - 1);
    final parts = _splitTypeArguments(body);
    return _WireType(
      base: base,
      arguments: parts.map(_WireType.parse).toList(growable: false),
      nullable: nullable,
    );
  }

  final String base;
  final List<_WireType> arguments;
  final bool nullable;

  String get nonNullableSource => arguments.isEmpty
      ? base
      : '$base<${arguments.map((type) => type.source).join(', ')}>';

  String get source => '$nonNullableSource${nullable ? '?' : ''}';
}

List<String> _splitTypeArguments(String source) {
  final values = <String>[];
  var start = 0;
  var angles = 0;
  var parentheses = 0;
  var brackets = 0;
  for (var index = 0; index < source.length; index++) {
    switch (source[index]) {
      case '<':
        angles++;
      case '>':
        angles--;
      case '(':
        parentheses++;
      case ')':
        parentheses--;
      case '[':
        brackets++;
      case ']':
        brackets--;
      case ',' when angles == 0 && parentheses == 0 && brackets == 0:
        values.add(source.substring(start, index).trim());
        start = index + 1;
    }
    if (angles < 0 || parentheses < 0 || brackets < 0) {
      throw FormatException('Malformed generic wire type $source');
    }
  }
  values.add(source.substring(start).trim());
  if (values.any((value) => value.isEmpty)) {
    throw FormatException('Malformed generic wire type $source');
  }
  return values;
}

const Set<String> _clientBuiltInTypes = <String>{
  'BigInt',
  'DateTime',
  'Duration',
  'Future',
  'Iterable',
  'List',
  'Map',
  'Never',
  'NoServerInput',
  'Null',
  'Object',
  'Set',
  'ServerResponse',
  'Stream',
  'String',
  'Uint8List',
  'Uri',
  'bool',
  'double',
  'dynamic',
  'int',
  'num',
  'void',
};

final class _ClientTypeVisitor extends RecursiveAstVisitor<void> {
  _ClientTypeVisitor(this.unsharedTypes);

  final Set<String> unsharedTypes;

  @override
  void visitNamedType(NamedType node) {
    final name = node.name.lexeme;
    if (node.importPrefix == null && !_clientBuiltInTypes.contains(name)) {
      unsharedTypes.add(name);
    }
    super.visitNamedType(node);
  }
}
