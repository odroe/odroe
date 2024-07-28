import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:odroe/config.dart';
import 'package:path/path.dart' as path;

import '../types.dart';

const _supportedMethods = [
  'get',
  'post',
  'put',
  'patch',
  'delete',
  'head',
  'options'
];

Manifest createServerManifest(OdroeConfig config, PageNode node) {
  final manifest = <Endpoint>[];
  if (node.files.contains(RouteFile.server)) {
    final endppint = _analyzeEndpoint(path.join(node.id, 'server.dart'));
    if (endppint != null) {
      manifest.add(endppint);
    }
  }

  for (final child in node.children) {
    manifest.addAll(createServerManifest(config, child));
  }

  return manifest;
}

Endpoint? _analyzeEndpoint(String path) {
  final server = parseFile(
    path: path,
    featureSet: FeatureSet.latestLanguageVersion(),
  ).unit;
  final functions = server.declarations.whereType<FunctionDeclaration>();
  final methods = functions
      .where((e) => _validateSpryRoute(e, _supportedMethods))
      .map((e) => e.name.lexeme);
  final fallback = functions
      .where((e) => _validateSpryRoute(e, const ['fallback']))
      .firstOrNull
      ?.name
      .lexeme;

  if (methods.isNotEmpty || fallback != null) {
    return (path: path, methods: methods, fallback: fallback);
  }

  return null;
}

bool _validateSpryRoute(
    FunctionDeclaration declaration, Iterable<String> allowNames) {
  // if not exports supported method.
  if (!allowNames.contains(declaration.name.toString().toLowerCase())) {
    return false;
  }

  // if the function is not signal params.
  else if (declaration.functionExpression.parameters?.parameters.length != 1) {
    return false;
  }

  final param =
      declaration.functionExpression.parameters?.parameters.singleOrNull;
  if (param?.isPositional == false || param?.isConst == true) {
    return false;
  }

  final type =
      param?.thisOrAncestorOfType<SimpleFormalParameter>()?.type?.toSource();

  return type == 'Event';
}
