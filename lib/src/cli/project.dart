import 'dart:io';

import 'package:args/args.dart';
import 'package:odroe/src/router_compiler/compiler.dart';
import 'package:path/path.dart' as p;

import '../atomic_write.dart';

/// Project paths and compiler state used by Odroe CLI commands.
final class CliProject {
  CliProject._({
    required this.root,
    required this.packageName,
    required this.compiler,
  });

  /// Resolves a project from parsed command arguments.
  factory CliProject.from(ArgResults arguments) {
    return CliProject._fromPaths(
      _absoluteDirectory(arguments.option('project')!),
      routesPath: arguments.option('routes')!,
      outputPath: arguments.option('output')!,
      serverOutputPath: arguments.option('server-output')!,
    );
  }

  /// Resolves a project using Odroe's conventional source paths.
  factory CliProject.fromRoot(String path) => CliProject._fromPaths(
    _absoluteDirectory(path),
    routesPath: 'lib/routes',
    outputPath: 'lib/routes.dart',
    serverOutputPath: 'lib/routes.server.dart',
  );

  factory CliProject._fromPaths(
    Directory root, {
    required String routesPath,
    required String outputPath,
    required String serverOutputPath,
  }) {
    final pubspec = File(p.join(root.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw FileSystemException('pubspec.yaml does not exist.', pubspec.path);
    }
    final match = RegExp(
      r'^name:\s*([A-Za-z_][A-Za-z0-9_]*)\s*$',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync());
    if (match == null) {
      throw FormatException('pubspec.yaml must declare a valid package name.');
    }
    final resolvedRoutesPath = _resolveProjectPath(
      root,
      routesPath,
      option: '--routes',
    );
    final resolvedOutputPath = _resolveProjectPath(
      root,
      outputPath,
      option: '--output',
    );
    final resolvedServerOutputPath = _resolveProjectPath(
      root,
      serverOutputPath,
      option: '--server-output',
    );
    return CliProject._(
      root: root,
      packageName: match.group(1)!,
      compiler: FileRouteCompiler(
        projectRoot: root,
        routesPath: resolvedRoutesPath,
        outputPath: resolvedOutputPath,
        serverOutputPath: resolvedServerOutputPath,
      ),
    );
  }

  /// The absolute project directory.
  final Directory root;

  /// The Dart package name declared by the project.
  final String packageName;

  /// The project's file-route compiler.
  final FileRouteCompiler compiler;

  /// The project's `lib` directory.
  Directory get libDirectory => Directory(p.join(root.path, 'lib'));

  /// The generated server bootstrap file.
  File get bootstrap =>
      File(p.join(root.path, '.dart_tool', 'odroe', 'server.dart'));

  /// The generated Fetch server bootstrap file.
  File get fetchBootstrap =>
      File(p.join(root.path, '.dart_tool', 'odroe', 'server_fetch.dart'));

  /// Whether the existing native bootstrap matches this project exactly.
  bool get bootstrapIsCurrent {
    if (!bootstrap.existsSync()) return false;
    return bootstrap.readAsStringSync() ==
        _bootstrapSource(
          packageName,
          customServer: File(
            p.join(libDirectory.path, 'server.dart'),
          ).existsSync(),
        );
  }

  /// Writes the current server bootstrap when its source changed.
  void writeBootstrap() {
    final source = _bootstrapSource(
      packageName,
      customServer: File(p.join(libDirectory.path, 'server.dart')).existsSync(),
    );
    _writeGenerated(bootstrap, source);
  }

  /// Writes the current Fetch server bootstrap when its source changed.
  void writeFetchBootstrap() {
    final source = _fetchBootstrapSource(
      packageName,
      customServer: File(p.join(libDirectory.path, 'server.dart')).existsSync(),
    );
    _writeGenerated(fetchBootstrap, source);
  }
}

Directory _absoluteDirectory(String path) =>
    Directory(p.normalize(Directory(path).absolute.path));

String _resolveProjectPath(
  Directory projectRoot,
  String relativePath, {
  required String option,
}) {
  if (relativePath.isEmpty || p.isAbsolute(relativePath)) {
    throw FormatException(
      '$option must be a relative path inside the project.',
    );
  }
  if (p.split(relativePath).contains('..')) {
    throw FormatException('$option cannot contain parent traversal.');
  }

  final root = p.normalize(projectRoot.absolute.path);
  final resolved = p.normalize(p.join(root, relativePath));
  if (!p.isWithin(root, resolved)) {
    throw FormatException('$option must resolve inside the project.');
  }

  var current = root;
  for (final component in p.split(p.relative(resolved, from: root))) {
    current = p.join(current, component);
    if (FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FormatException('$option cannot traverse a symbolic link.');
    }
  }
  return p.relative(resolved, from: root);
}

/// Generates project routes and reports diagnostics to [err].
FileRouteOutput? generateRoutes(
  CliProject project,
  StringSink out,
  StringSink err,
) {
  try {
    final result = project.compiler.write();
    project.writeBootstrap();
    out.writeln(
      result.changed
          ? 'Generated ${project.compiler.outputFile.path} and '
                '${project.compiler.serverOutputFile.path} '
                '(${result.routeCount} routes).'
          : 'Generated routes are current (${result.routeCount} routes).',
    );
    return result;
  } on FileRouteCompilationException catch (error) {
    for (final diagnostic in error.diagnostics) {
      err.writeln(diagnostic);
    }
    return null;
  }
}

/// Starts [executable] inside [project] with inherited standard IO.
Future<Process> startProjectProcess(
  String executable,
  List<String> arguments, {
  required CliProject project,
  Map<String, String>? environment,
}) => Process.start(
  executable,
  arguments,
  workingDirectory: project.root.path,
  environment: environment,
  mode: ProcessStartMode.inheritStdio,
);

void _writeGenerated(File file, String source) {
  writeStringIfChanged(file, source);
}

String _bootstrapSource(String packageName, {required bool customServer}) =>
    '''
// Generated by Odroe. Do not edit.
import 'dart:async';
import 'dart:io';

import 'package:odroe/server_io.dart';
import 'package:$packageName/${customServer ? 'server.dart' : 'routes.server.dart'}' as app;

Future<void> main() async {
  final platformPort = Platform.environment['PORT'];
  final host =
      Platform.environment['ODROE_HOST'] ??
      (platformPort == null ? '127.0.0.1' : '0.0.0.0');
  final port = int.parse(
    Platform.environment['ODROE_PORT'] ??
        platformPort ??
        '3000',
  );
  final webRoot = Platform.environment['ODROE_WEB_ROOT'];
  final developmentOriginFile =
      Platform.environment['ODROE_FLUTTER_ORIGIN_FILE'];
  final appServer = await app.createServer();
  HttpServer? nativeServer;
  Object? primaryError;
  StackTrace? primaryStackTrace;
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  try {
    nativeServer = await IoServer.bind(
      appServer.handler,
      onError: appServer.onError,
      address: host,
      port: port,
      publicDirectory: webRoot == '' ? null : Directory(webRoot ?? 'build/web'),
      developmentProxyOriginFile:
          developmentOriginFile == null || developmentOriginFile == ''
          ? null
          : File(developmentOriginFile),
    );
    stdout.writeln(
      'Odroe listening on http://\${nativeServer.address.host}:\${nativeServer.port}',
    );
    final stopping = Completer<void>();
    void stop(ProcessSignal _) {
      if (!stopping.isCompleted) {
        stopping.complete();
        return;
      }
      IoServer.close(nativeServer!, force: true).ignore();
    }
    subscriptions.add(ProcessSignal.sigint.watch().listen(stop));
    if (!Platform.isWindows) {
      subscriptions.add(ProcessSignal.sigterm.watch().listen(stop));
    }
    await stopping.future;
  } on Object catch (error, stackTrace) {
    primaryError = error;
    primaryStackTrace = stackTrace;
  }
  try {
    await _closeNativeApplication(nativeServer, appServer);
  } on Object catch (error, stackTrace) {
    if (primaryError == null) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    } else {
      _reportSecondaryCleanupError(error, stackTrace);
    }
  }
  try {
    await Future.wait<void>([
      for (final subscription in subscriptions) subscription.cancel(),
    ]);
  } on Object catch (error, stackTrace) {
    if (primaryError == null) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    } else {
      _reportSecondaryCleanupError(error, stackTrace);
    }
  }
  if (primaryError != null) {
    Error.throwWithStackTrace(primaryError, primaryStackTrace!);
  }
}

Future<void> _closeNativeApplication(
  HttpServer? nativeServer,
  Server appServer,
) async {
  Object? primaryError;
  StackTrace? primaryStackTrace;
  if (nativeServer != null) {
    try {
      await IoServer.close(nativeServer);
    } on Object catch (error, stackTrace) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    }
  }
  try {
    await appServer.close();
  } on Object catch (error, stackTrace) {
    if (primaryError == null) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    } else {
      _reportSecondaryCleanupError(error, stackTrace);
    }
  }
  if (primaryError != null) {
    Error.throwWithStackTrace(primaryError, primaryStackTrace!);
  }
}

void _reportSecondaryCleanupError(Object error, StackTrace stackTrace) {
  try {
    Zone.current.print('Secondary Odroe cleanup error: \$error\\n\$stackTrace');
  } on Object {
    // Cleanup reporting must not replace the primary failure.
  }
}
''';

String _fetchBootstrapSource(
  String packageName, {
  required bool customServer,
}) =>
    '''
// Generated by Odroe. Do not edit.
import 'package:odroe/server_fetch.dart';
import 'package:$packageName/${customServer ? 'server.dart' : 'routes.server.dart'}' as app;

void main() {
  final appServer = app.createServer();
  exportFetchHandler(
    appServer.invocationHandler,
    onError: appServer.onError,
  );
}
''';
