import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/server_io.dart';
import 'package:path/path.dart' as p;

import 'project.dart';

/// Builds the selected Flutter target and Odroe server artifact.
Future<int> runBuild(
  CliProject project, {
  required bool serverOnly,
  required bool buildServer,
  required String serverArtifact,
  required bool prerender,
  required String prerenderOutput,
  required int prerenderConcurrency,
  required List<String> flutterArguments,
  required StringSink out,
  required StringSink err,
}) async {
  final inspected = project.compiler.compile();
  if (inspected.hasErrors) {
    for (final diagnostic in inspected.diagnostics) {
      err.writeln(diagnostic);
    }
    return 1;
  }
  if (serverOnly && !buildServer) {
    err.writeln('--server-only cannot be combined with --no-server.');
    return 64;
  }
  if (!serverOnly && inspected.hasFlutter && flutterArguments.isEmpty) {
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
      (!inspected.hasFlutter || flutterTarget == 'web');
  if (shouldPrerender && !buildServer) {
    err.writeln('Prerendering requires the Odroe server artifact.');
    return 64;
  }
  final outputDirectory = shouldPrerender
      ? _validateOutput(
          project,
          prerenderOutput,
          serverArtifact,
          hasFlutter: inspected.hasFlutter,
        )
      : null;
  final generated = generateRoutes(project, out, err, compiled: inspected);
  if (generated == null) return 1;
  late final File artifact;
  if (buildServer) {
    artifact = File(p.join(project.root.path, serverArtifact)).absolute;
    artifact.parent.createSync(recursive: true);
    final process = await startProjectProcess(
      Platform.resolvedExecutable,
      <String>['compile', 'exe', project.bootstrap.path, '-o', artifact.path],
      project: project,
    );
    final code = await process.exitCode;
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
  final output = outputDirectory!;
  output.parent.createSync(recursive: true);
  final staging = generated.hasFlutter
      ? output
      : output.parent.createTempSync('.odroe-prerender-');
  try {
    staging.createSync(recursive: true);
    final assets = await _copyPublicAssets(project, staging);
    if (assets > 0) out.writeln('Copied $assets public assets.');
    final code = await _prerenderBuild(
      project,
      artifact: artifact,
      routes: generated.staticRoutes,
      outputDirectory: staging,
      concurrency: prerenderConcurrency,
      out: out,
      err: err,
    );
    if (code != 0 || generated.hasFlutter) return code;
    // Recheck ownership before replacing an output that may have changed.
    _validateOutput(
      project,
      prerenderOutput,
      serverArtifact,
      hasFlutter: false,
    );
    File(
      p.join(staging.path, _outputMarker),
    ).writeAsStringSync('odroe-prerender-v1:${project.packageName}\n');
    Directory? backup;
    if (output.existsSync()) {
      backup = output.parent.createTempSync('.odroe-prerender-backup-');
      backup.deleteSync();
      output.renameSync(backup.path);
    }
    try {
      staging.renameSync(output.path);
    } on Object {
      if (backup != null) {
        try {
          backup.renameSync(output.path);
        } on FileSystemException catch (restoreError) {
          err.writeln(
            'Could not restore previous output; it remains at '
            '${backup.path}: ${restoreError.message}',
          );
        }
      }
      rethrow;
    }
    if (backup != null) {
      try {
        backup.deleteSync(recursive: true);
      } on FileSystemException catch (error) {
        err.writeln(
          'Warning: Output was published, but the previous output remains at '
          '${backup.path}: ${error.message}',
        );
      }
    }
    return 0;
  } finally {
    if (!generated.hasFlutter && staging.existsSync()) {
      try {
        staging.deleteSync(recursive: true);
      } on FileSystemException catch (error) {
        err.writeln(
          'Warning: Prerender staging remains at ${staging.path}: '
          '${error.message}',
        );
      }
    }
  }
}

const _outputMarker = '.odroe-prerender';

Directory _validateOutput(
  CliProject project,
  String relative,
  String serverArtifact, {
  required bool hasFlutter,
}) {
  final root = p.normalize(project.root.absolute.path);
  final path = p.normalize(p.join(root, relative));
  if (relative.isEmpty ||
      p.isAbsolute(relative) ||
      p.split(relative).contains('..') ||
      !p.isWithin(p.join(root, 'build'), path)) {
    throw const FormatException(
      '--prerender-output must be a relative path inside build/.',
    );
  }
  var current = root;
  for (final component in p.split(p.relative(path, from: root))) {
    current = p.join(current, component);
    if (FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException(
        '--prerender-output cannot traverse a symbolic link.',
      );
    }
  }
  final realOutput = _realPathForOverlap(path);
  bool overlaps(String other) {
    final normalized = _realPathForOverlap(other);
    return p.equals(realOutput, normalized) ||
        p.isWithin(realOutput, normalized) ||
        p.isWithin(normalized, realOutput);
  }

  if (<String>[
    p.join(root, 'public'),
    project.compiler.routesDirectory.path,
    project.compiler.outputFile.path,
    project.compiler.serverOutputFile.path,
    p.join(root, serverArtifact),
  ].any(overlaps)) {
    throw const FormatException(
      'Prerender output must not overlap sources or server artifacts.',
    );
  }
  if (FileSystemEntity.typeSync(p.join(root, 'public'), followLinks: false) ==
      FileSystemEntityType.link) {
    throw const FormatException('Public assets must not be a symbolic link.');
  }
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.directory) {
    throw const FormatException(
      'Prerender output must be a regular directory.',
    );
  }
  final output = Directory(path);
  if (!hasFlutter && output.existsSync()) {
    final marker = File(p.join(path, _outputMarker));
    if (FileSystemEntity.typeSync(marker.path, followLinks: false) !=
            FileSystemEntityType.file ||
        marker.readAsStringSync() !=
            'odroe-prerender-v1:${project.packageName}\n') {
      throw const FormatException(
        'Existing prerender output is not owned by this Odroe project; choose a new output directory.',
      );
    }
  }
  return output;
}

String _realPathForOverlap(String path) {
  var existing = p.normalize(p.absolute(path));
  final suffix = <String>[];
  while (FileSystemEntity.typeSync(existing, followLinks: false) ==
      FileSystemEntityType.notFound) {
    final parent = p.dirname(existing);
    if (p.equals(parent, existing)) break;
    suffix.insert(0, p.basename(existing));
    existing = parent;
  }
  final resolved = Directory(existing).resolveSymbolicLinksSync();
  return p.normalize(p.joinAll(<String>[resolved, ...suffix]));
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
  final stdoutDone = process.stdout
      .transform(systemEncoding.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        final match = RegExp(r'https?://[^\s]+').firstMatch(line);
        final origin = match == null ? null : Uri.tryParse(match.group(0)!);
        if (origin != null && !ready.isCompleted) ready.complete(origin);
      })
      .asFuture<void>();
  final stderrDone = process.stderr
      .transform(systemEncoding.decoder)
      .listen(err.write)
      .asFuture<void>();
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
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
  }
}
