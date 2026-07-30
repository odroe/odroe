import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/server_io.dart';
import 'package:path/path.dart' as p;

import 'prerender_manifest.dart';
import 'project.dart';

/// Server artifact selected by `odroe build`.
enum ServerBuildTarget {
  /// A standalone Dart VM executable.
  native,

  /// A JavaScript module for Cloudflare Workers.
  cloudflare,
}

/// Builds the selected Flutter target and Odroe server artifact.
Future<int> runBuild(
  CliProject project, {
  required bool serverOnly,
  required bool buildServer,
  required ServerBuildTarget serverTarget,
  required String? serverArtifact,
  required bool prerender,
  required String prerenderOutput,
  required int prerenderConcurrency,
  required List<String> flutterArguments,
  required StringSink out,
  required StringSink err,
}) async {
  final generated = generateRoutes(project, out, err);
  if (generated == null) return 1;
  if (serverOnly && !buildServer) {
    err.writeln('--server-only cannot be combined with --no-server.');
    return 64;
  }
  if (!serverOnly && generated.hasFlutter && flutterArguments.isEmpty) {
    err.writeln(
      'Choose a Flutter build target, for example: '
      'dart run odroe build apk or dart run odroe build web.',
    );
    return 64;
  }
  final flutterTarget = flutterArguments
      .where((argument) => !argument.startsWith('-'))
      .firstOrNull;
  final shouldPrerender =
      prerender &&
      !serverOnly &&
      (!generated.hasFlutter || flutterTarget == 'web');
  if (shouldPrerender && !buildServer) {
    err.writeln('Prerendering requires the Odroe server artifact.');
    return 64;
  }
  late final Directory outputDirectory;
  if (shouldPrerender) {
    outputDirectory = Directory(
      resolveBuildOutputPath(
        project.root,
        prerenderOutput,
        option: '--prerender-output',
      ),
    );
  }
  late final File artifact;
  if (buildServer) {
    artifact = File(
      resolveBuildOutputPath(
        project.root,
        serverArtifact ?? _defaultServerArtifact(serverTarget),
        option: '--server-artifact',
      ),
    );
    final code = await _buildServer(
      project,
      target: serverTarget,
      artifact: artifact,
      out: out,
    );
    if (code != 0) return code;
  }
  if (!serverOnly && flutterArguments.isNotEmpty) {
    final flutter = await startProjectProcess('flutter', <String>[
      'build',
      ...flutterArguments,
    ], project: project);
    final code = await flutter.exitCode;
    if (code != 0) return code;
  }
  if (!shouldPrerender) return 0;
  if (!generated.hasFlutter && outputDirectory.existsSync()) {
    outputDirectory.deleteSync(recursive: true);
  }
  outputDirectory.createSync(recursive: true);
  final assets = await _copyPublicAssets(project, outputDirectory);
  if (assets > 0) out.writeln('Copied $assets public assets.');
  final routes = await loadPrerenderLocations(
    projectRoot: project.root,
    packageName: project.packageName,
    staticLocations: generated.staticRoutes,
  );
  File prerenderArtifact = artifact;
  var removePrerenderArtifact = false;
  if (serverTarget == ServerBuildTarget.cloudflare) {
    prerenderArtifact = File(
      p.join(project.root.path, '.dart_tool', 'odroe', 'prerender-server'),
    ).absolute;
    final code = await _compileNativeServer(project, prerenderArtifact);
    if (code != 0) return code;
    removePrerenderArtifact = true;
  }
  try {
    return await _prerenderBuild(
      project,
      artifact: prerenderArtifact,
      routes: routes,
      outputDirectory: outputDirectory,
      concurrency: prerenderConcurrency,
      out: out,
      err: err,
    );
  } finally {
    if (removePrerenderArtifact && prerenderArtifact.existsSync()) {
      prerenderArtifact.deleteSync();
    }
  }
}

String _defaultServerArtifact(ServerBuildTarget target) => switch (target) {
  ServerBuildTarget.native => 'build/odroe/server',
  ServerBuildTarget.cloudflare => 'build/odroe/cloudflare/server.js',
};

/// Resolves one user-selected artifact path inside a project's real build tree.
///
/// Absolute paths, parent traversal, the build directory itself, and existing
/// symbolic-link components are rejected before any write or recursive delete.
String resolveBuildOutputPath(
  Directory projectRoot,
  String relativePath, {
  required String option,
}) {
  if (relativePath.isEmpty || p.isAbsolute(relativePath)) {
    throw FormatException('$option must be a relative path inside build/.');
  }
  if (p.split(relativePath).contains('..')) {
    throw FormatException('$option cannot contain parent traversal.');
  }

  final root = p.normalize(projectRoot.absolute.path);
  final buildRoot = p.normalize(p.join(root, 'build'));
  final resolved = p.normalize(p.join(root, relativePath));
  if (!p.isWithin(buildRoot, resolved)) {
    throw FormatException('$option must resolve inside build/.');
  }

  var current = root;
  for (final component in p.split(p.relative(resolved, from: root))) {
    current = p.join(current, component);
    if (FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FormatException('$option cannot traverse a symbolic link.');
    }
  }
  return resolved;
}

Future<int> _buildServer(
  CliProject project, {
  required ServerBuildTarget target,
  required File artifact,
  required StringSink out,
}) async {
  artifact.parent.createSync(recursive: true);
  if (target == ServerBuildTarget.native) {
    return _compileNativeServer(project, artifact);
  }
  if (p.extension(artifact.path) != '.js') {
    throw const FormatException(
      'Cloudflare server artifacts must use the .js extension.',
    );
  }
  project.writeFetchBootstrap();
  final process =
      await startProjectProcess(Platform.resolvedExecutable, <String>[
        'compile',
        'js',
        '-O4',
        '--no-source-maps',
        project.fetchBootstrap.path,
        '-o',
        artifact.path,
      ], project: project);
  final code = await process.exitCode;
  if (code != 0) return code;

  final worker = File(p.join(artifact.parent.path, 'worker.mjs'));
  _writeTextAtomically(
    worker,
    _cloudflareWorkerSource(p.basename(artifact.path)),
  );
  out.writeln(
    'Built Cloudflare Worker -> '
    '${p.relative(worker.path, from: project.root.path)}',
  );
  return 0;
}

Future<int> _compileNativeServer(CliProject project, File artifact) async {
  artifact.parent.createSync(recursive: true);
  final process = await startProjectProcess(
    Platform.resolvedExecutable,
    <String>['compile', 'exe', project.bootstrap.path, '-o', artifact.path],
    project: project,
  );
  return process.exitCode;
}

String _cloudflareWorkerSource(String serverFile) =>
    '''
import ${jsonEncode('./$serverFile')};

export default {
  fetch(request, env, context) {
    return globalThis.__odroeFetch(request, env, context);
  },
};
''';

void _writeTextAtomically(File file, String source) {
  if (file.existsSync() && file.readAsStringSync() == source) return;
  final temporary = File('${file.path}.tmp');
  try {
    temporary.writeAsStringSync(source);
    temporary.renameSync(file.path);
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
}

Future<int> _copyPublicAssets(CliProject project, Directory output) async {
  final source = Directory(p.join(project.root.path, 'public')).absolute;
  if (!source.existsSync()) return 0;
  if (p.equals(source.path, output.path) ||
      p.isWithin(source.path, output.path)) {
    throw FileSystemException(
      'Prerender output cannot be inside the public directory.',
      output.path,
    );
  }
  var files = 0;
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    if (entity is Link) continue;
    final relative = p.relative(entity.path, from: source.path);
    final target = p.normalize(p.join(output.path, relative));
    if (!p.isWithin(output.path, target)) continue;
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      final file = File(target);
      file.parent.createSync(recursive: true);
      await entity.copy(file.path);
      files++;
    }
  }
  return files;
}

Future<int> _prerenderBuild(
  CliProject project, {
  required File artifact,
  required List<String> routes,
  required Directory outputDirectory,
  required int concurrency,
  required StringSink out,
  required StringSink err,
}) async {
  if (routes.isEmpty) {
    out.writeln('No static routes to prerender.');
    return 0;
  }
  final process = await Process.start(
    artifact.path,
    const <String>[],
    workingDirectory: project.root.path,
    environment: <String, String>{
      ...Platform.environment,
      'ODROE_HOST': '127.0.0.1',
      'ODROE_PORT': '0',
      'ODROE_WEB_ROOT': outputDirectory.path,
    },
  );
  final ready = Completer<Uri>();
  final stdoutSubscription = process.stdout
      .transform(systemEncoding.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        final origin = parsePrerenderReadyLine(line);
        if (origin != null && !ready.isCompleted) ready.complete(origin);
      });
  final stderrSubscription = process.stderr
      .transform(systemEncoding.decoder)
      .listen(err.write);
  final stdoutDone = stdoutSubscription.asFuture<void>();
  final stderrDone = stderrSubscription.asFuture<void>();
  unawaited(
    process.exitCode.then((code) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError('Odroe server exited with code $code before listening.'),
        );
      }
    }),
  );

  try {
    final origin = await ready.future.timeout(const Duration(seconds: 20));
    final rendered = await Prerenderer().render(
      origin: origin,
      routes: routes,
      output: outputDirectory,
      concurrency: concurrency,
      crawlLinks: true,
    );
    for (final route in rendered) {
      final relative = p.relative(route.file.path, from: project.root.path);
      out.writeln(
        'Prerendered ${route.route} -> $relative '
        '(${route.elapsed.inMilliseconds}ms)',
      );
    }
    out.writeln('Prerendered ${rendered.length} routes.');
    return 0;
  } on Object catch (error) {
    err.writeln(error);
    return 1;
  } finally {
    await _stopPrerenderServer(
      process,
      stdoutDone,
      stderrDone,
      () => Future.wait<void>(<Future<void>>[
        stdoutSubscription.cancel(),
        stderrSubscription.cancel(),
      ], eagerError: false),
    );
  }
}

Future<void> _stopPrerenderServer(
  Process process,
  Future<void> stdoutDone,
  Future<void> stderrDone,
  Future<void> Function() cancelOutput,
) async {
  const gracePeriod = Duration(seconds: 10);
  process.kill(ProcessSignal.sigterm);
  try {
    await process.exitCode.timeout(gracePeriod);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode.timeout(gracePeriod);
    } on TimeoutException {
      // Do not let an unresponsive process hold the build open forever.
    }
  }
  try {
    await Future.wait<void>(<Future<void>>[
      stdoutDone,
      stderrDone,
    ], eagerError: false).timeout(gracePeriod);
    return;
  } on Object {
    // A descendant may still own an inherited pipe handle.
  }
  try {
    await cancelOutput().timeout(gracePeriod);
  } on Object {
    // Process output is diagnostic; cleanup must not replace the build result.
  }
}

/// Parses the one readiness line emitted by Odroe's generated native server.
///
/// Arbitrary application logs must never select the prerender origin.
Uri? parsePrerenderReadyLine(String line) {
  final match = RegExp(
    r'^Odroe listening on http://127\.0\.0\.1:([0-9]+)$',
  ).firstMatch(line);
  if (match == null) return null;
  final port = int.tryParse(match.group(1)!);
  if (port == null || port < 1 || port > 65535) return null;
  return Uri(scheme: 'http', host: '127.0.0.1', port: port);
}
