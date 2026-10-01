import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'build.dart';
import 'project.dart';

/// Builds and watches an Odroe server in a project-local Cloudflare runtime.
Future<int> runCloudflareDevelopment(
  CliProject project, {
  required String host,
  required int port,
  required bool serverOnly,
  required List<String> flutterArguments,
  required StringSink out,
  required StringSink err,
}) async {
  if (!serverOnly) {
    err.writeln(
      'Cloudflare development currently requires --server-only. '
      'Run Flutter separately when needed.',
    );
    return 64;
  }
  if (flutterArguments.isNotEmpty) {
    err.writeln(
      'Cloudflare server-only development does not accept Flutter arguments.',
    );
    return 64;
  }

  final wrangler = _projectWrangler(project);
  if (!wrangler.existsSync()) {
    err.writeln(
      'Project-local Wrangler does not exist at ${wrangler.path}. '
      'Run npm ci in the application first.',
    );
    return 1;
  }
  final config = File(p.join(project.root.path, 'wrangler.jsonc'));
  if (!config.existsSync()) {
    err.writeln(
      'wrangler.jsonc does not exist at ${config.path}. '
      'Cloudflare bindings and local runtime policy must remain '
      'application-owned.',
    );
    return 1;
  }

  final generated = generateRoutes(project, out, err);
  if (generated == null) return 1;
  final artifact = File(
    resolveBuildOutputPath(
      project.root,
      'build/odroe/cloudflare/server.js',
      option: 'Cloudflare development artifact',
    ),
  );
  final initialBuild = await buildCloudflareServer(
    project,
    artifact: artifact,
    out: out,
  );
  if (initialBuild != 0) return initialBuild;

  final done = Completer<int>();
  final stoppingSignal = Completer<void>();
  var stopping = false;
  void beginStopping() {
    stopping = true;
    if (!stoppingSignal.isCompleted) stoppingSignal.complete();
  }

  Timer? debounce;
  var serverBuildNeeded = false;
  var rebuildQueued = false;
  var rebuilding = false;
  Future<void>? activeRebuild;
  Future<void> rebuild() async {
    if (stopping) return;
    rebuilding = true;
    try {
      do {
        rebuildQueued = false;
        final shouldBuildServer = serverBuildNeeded;
        serverBuildNeeded = false;
        try {
          final generated = generateRoutes(project, out, err);
          if (generated == null || !shouldBuildServer) continue;
          final code = await buildCloudflareServer(
            project,
            artifact: artifact,
            out: out,
            cancelled: stoppingSignal.future,
          );
          if (code != 0 && !stopping) {
            err.writeln(
              'Cloudflare rebuild failed; keeping the previous Worker.',
            );
          }
        } on Object catch (error) {
          if (stopping) continue;
          err.writeln(
            'Cloudflare rebuild failed; keeping the previous Worker. $error',
          );
        }
      } while (rebuildQueued && !stopping);
    } finally {
      rebuilding = false;
    }
  }

  StreamSubscription<FileSystemEvent>? changes;
  final signals = <StreamSubscription<ProcessSignal>>[];
  Process? runtime;
  Future<int>? runtimeExitCode;

  void sourceChanged(FileSystemEvent event) {
    if (stopping || !event.path.endsWith('.dart')) return;
    if (p.equals(event.path, project.compiler.outputFile.path) ||
        p.equals(event.path, project.compiler.serverOutputFile.path)) {
      return;
    }
    final name = p.basename(event.path);
    final flutterOnlyModification =
        event.type == FileSystemEvent.modify &&
        p.isWithin(project.compiler.routesDirectory.path, event.path) &&
        (name == 'page.dart' || name == 'shell.dart');
    serverBuildNeeded |= !flutterOnlyModification;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 120), () {
      if (stopping) return;
      if (rebuilding) {
        rebuildQueued = true;
        return;
      }
      activeRebuild = rebuild();
    });
  }

  void stop(ProcessSignal _) {
    if (done.isCompleted) return;
    beginStopping();
    done.complete(0);
  }

  Future<void> clean(String target, Future<void> Function() cleanup) async {
    try {
      await cleanup();
    } on Object catch (error) {
      err.writeln('Could not stop $target. $error');
    }
  }

  try {
    changes = project.libDirectory
        .watch(recursive: true)
        .listen(
          sourceChanged,
          onError: (Object error) {
            if (stopping || done.isCompleted) return;
            err.writeln('Cloudflare source watcher failed. $error');
            done.complete(1);
          },
        );
    final worker = File(p.join(artifact.parent.path, 'worker.mjs'));
    runtime = await startProjectProcess('node', <String>[
      wrangler.path,
      'dev',
      p.relative(worker.path, from: project.root.path),
      '--config',
      config.path,
      '--local',
      '--ip',
      host,
      '--port',
      '$port',
    ], project: project);
    runtimeExitCode = runtime.exitCode;
    unawaited(
      runtimeExitCode.then((code) {
        if (!stopping && !done.isCompleted) done.complete(code);
      }),
    );
    signals.add(ProcessSignal.sigint.watch().listen(stop));
    if (!Platform.isWindows) {
      signals.add(ProcessSignal.sigterm.watch().listen(stop));
    }
    return await done.future;
  } finally {
    beginStopping();
    debounce?.cancel();
    await clean('Cloudflare source watcher', () async {
      await changes?.cancel();
    });
    for (final signal in signals) {
      await clean('Cloudflare signal watcher', signal.cancel);
    }
    await Future.wait<void>(<Future<void>>[
      if (runtime case final runningRuntime?)
        clean('Wrangler', () async {
          await _terminateProcess(runningRuntime, runtimeExitCode!);
        }),
      clean('Cloudflare compiler', () async {
        try {
          await activeRebuild?.timeout(const Duration(seconds: 12));
        } on TimeoutException {
          err.writeln('Cloudflare compiler did not stop within 12 seconds.');
        }
      }),
    ]);
  }
}

File _projectWrangler(CliProject project) => File(
  p.join(project.root.path, 'node_modules', 'wrangler', 'bin', 'wrangler.js'),
);

Future<void> _terminateProcess(Process process, Future<int> exitCode) async {
  process.kill(ProcessSignal.sigterm);
  try {
    await exitCode.timeout(const Duration(seconds: 5));
    return;
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
  }
  try {
    await exitCode.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    // Never keep the CLI alive forever for an unresponsive child process.
  }
}
