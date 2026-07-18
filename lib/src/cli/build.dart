// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/start_io.dart';
import 'package:path/path.dart' as p;

import 'project.dart';

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
    err.writeln('Prerendering requires the Start server artifact.');
    return 64;
  }
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
  final outputDirectory = Directory(
    p.join(project.root.path, prerenderOutput),
  ).absolute;
  if (!generated.hasFlutter && outputDirectory.existsSync()) {
    outputDirectory.deleteSync(recursive: true);
  }
  outputDirectory.createSync(recursive: true);
  final assets = await _copyPublicAssets(project, outputDirectory);
  if (assets > 0) out.writeln('Copied $assets public assets.');
  return _prerenderBuild(
    project,
    artifact: artifact,
    routes: generated.staticRoutes,
    outputDirectory: outputDirectory,
    concurrency: prerenderConcurrency,
    out: out,
    err: err,
  );
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
          StateError('Start server exited with code $code before listening.'),
        );
      }
    }),
  );

  try {
    final origin = await ready.future.timeout(const Duration(seconds: 20));
    final result = await StartPrerenderer().render(
      origin: origin,
      routes: routes,
      output: outputDirectory,
      options: StartPrerenderOptions(
        concurrency: concurrency,
        crawlLinks: true,
        failOnError: true,
      ),
    );
    for (final route in result.routes) {
      final relative = p.relative(route.file.path, from: project.root.path);
      out.writeln(
        'Prerendered ${route.route} -> $relative '
        '(${route.elapsed.inMilliseconds}ms)',
      );
    }
    out.writeln('Prerendered ${result.routes.length} routes.');
    return 0;
  } on StartPrerenderException catch (error) {
    for (final failure in error.failures) {
      err.writeln('Failed ${failure.route}: ${failure.error}');
    }
    return 1;
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
