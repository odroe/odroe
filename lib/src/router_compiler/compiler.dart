// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;

import 'generator.dart';
import 'model.dart';
import 'scanner.dart';

export 'model.dart'
    show
        FileRouteCompilationException,
        FileRouteDiagnostic,
        FileRouteDiagnosticSeverity,
        FileRouteOutput;

/// Compiles `lib/routes/` into client and server route targets.
final class FileRouteCompiler {
  FileRouteCompiler({
    required Directory projectRoot,
    String routesPath = 'lib/routes',
    String outputPath = 'lib/routes.dart',
    String serverOutputPath = 'lib/routes.server.dart',
  }) : projectRoot = projectRoot.absolute,
       routesDirectory = Directory(
         p.join(projectRoot.absolute.path, routesPath),
       ),
       outputFile = File(p.join(projectRoot.absolute.path, outputPath)),
       serverOutputFile = File(
         p.join(projectRoot.absolute.path, serverOutputPath),
       );

  final Directory projectRoot;
  final Directory routesDirectory;
  final File outputFile;
  final File serverOutputFile;

  FileRouteOutput compile() {
    final diagnostics = <FileRouteDiagnostic>[];
    if (!routesDirectory.existsSync()) {
      diagnostics.add(
        FileRouteDiagnostic(
          severity: FileRouteDiagnosticSeverity.error,
          path: _relative(routesDirectory.path),
          message: 'Routes directory does not exist.',
        ),
      );
      return FileRouteOutput(
        source: '',
        serverSource: '',
        diagnostics: diagnostics,
        routeCount: 0,
        staticRoutes: const <String>[],
        hasFlutter: false,
      );
    }

    final scanner = RouteScanner(projectRoot);
    final root = scanner.scan(routesDirectory, diagnostics);
    final nodes = scanner.flatten(root);
    scanner.validate(root, nodes, diagnostics);
    var source = '';
    var serverSource = '';
    if (!diagnostics.any(
      (diagnostic) => diagnostic.severity == FileRouteDiagnosticSeverity.error,
    )) {
      final generator = RouteGenerator(
        projectRoot: projectRoot,
        outputFile: outputFile,
        serverOutputFile: serverOutputFile,
      );
      try {
        source = generator.generateClient(nodes);
        serverSource = generator.generateServer(root, nodes);
      } on FormatterException catch (error) {
        diagnostics.add(
          FileRouteDiagnostic(
            severity: FileRouteDiagnosticSeverity.error,
            path: _relative(outputFile.path),
            message: 'Generated route source is invalid: $error',
          ),
        );
      }
    }
    return FileRouteOutput(
      source: source,
      serverSource: serverSource,
      diagnostics: diagnostics,
      routeCount: nodes.length,
      staticRoutes: scanner.staticRoutes(nodes),
      hasFlutter: nodes.any(
        (node) => node.pageFile != null || node.shellFile != null,
      ),
    );
  }

  FileRouteOutput write() {
    final output = compile();
    if (output.hasErrors) {
      throw FileRouteCompilationException(output.diagnostics);
    }
    final clientChanged = _writeIfChanged(outputFile, output.source);
    final serverChanged = _writeIfChanged(
      serverOutputFile,
      output.serverSource,
    );
    if (!clientChanged && !serverChanged) return output;
    return FileRouteOutput(
      source: output.source,
      serverSource: output.serverSource,
      diagnostics: output.diagnostics,
      routeCount: output.routeCount,
      staticRoutes: output.staticRoutes,
      hasFlutter: output.hasFlutter,
      changed: true,
    );
  }

  bool _writeIfChanged(File target, String source) {
    if (target.existsSync() && target.readAsStringSync() == source) {
      return false;
    }
    target.parent.createSync(recursive: true);
    final temporary = File('${target.path}.tmp');
    try {
      temporary.writeAsStringSync(source);
      temporary.renameSync(target.path);
    } finally {
      if (temporary.existsSync()) {
        temporary.deleteSync();
      }
    }
    return true;
  }

  String _relative(String path) => p.relative(path, from: projectRoot.path);
}
