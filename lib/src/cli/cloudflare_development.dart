import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'build.dart';
import 'project.dart';

/// Compiler dependency used by the CLI's controlled startup regressions.
typedef CloudflareDevelopmentCompiler =
    Future<int> Function(
      CliProject project, {
      required File artifact,
      required StringSink out,
      Future<void>? cancelled,
    });

/// Builds and watches an Odroe server in a project-local Cloudflare runtime.
Future<int> runCloudflareDevelopment(
  CliProject project, {
  required String host,
  required int port,
  required bool serverOnly,
  required List<String> flutterArguments,
  required StringSink out,
  required StringSink err,
  CloudflareDevelopmentCompiler compiler = buildCloudflareServer,
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

  final artifact = File(
    resolveBuildOutputPath(
      project.root,
      'build/odroe/cloudflare/server.js',
      option: 'Cloudflare development artifact',
    ),
  );

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
  // Source events are queued until the initial compile finishes.
  var rebuilding = true;
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
          final code = await compiler(
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

  StreamSubscription<WatchEvent>? changes;
  final signals = <StreamSubscription<ProcessSignal>>[];
  Process? runtime;
  Future<int>? runtimeExitCode;

  void sourceChanged(WatchEvent event) {
    if (stopping || !event.path.endsWith('.dart')) return;
    if (p.equals(event.path, project.compiler.outputFile.path) ||
        p.equals(event.path, project.compiler.serverOutputFile.path)) {
      return;
    }
    final name = p.basename(event.path);
    final flutterOnlyModification =
        event.type == ChangeType.MODIFY &&
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
    project.libDirectory.createSync(recursive: true);
    final sourceWatcher = DirectoryWatcher(project.libDirectory.path);
    changes = sourceWatcher.events.listen(
      sourceChanged,
      onError: (Object error) {
        if (stopping || done.isCompleted) return;
        err.writeln('Cloudflare source watcher failed. $error');
        beginStopping();
        done.complete(1);
      },
    );
    await Future.any<void>(<Future<void>>[
      sourceWatcher.ready.then<void>((_) {}),
      done.future.then<void>((_) {}),
    ]);
    if (done.isCompleted) return await done.future;
    signals.add(ProcessSignal.sigint.watch().listen(stop));
    if (!Platform.isWindows) {
      signals.add(ProcessSignal.sigterm.watch().listen(stop));
    }
    final generated = generateRoutes(project, out, err);
    if (generated == null) return 1;
    final initialBuild = await compiler(
      project,
      artifact: artifact,
      out: out,
      cancelled: stoppingSignal.future,
    );
    if (done.isCompleted) return await done.future;
    if (initialBuild != 0) return initialBuild;
    final startupChanges =
        serverBuildNeeded || rebuildQueued || debounce != null;
    debounce?.cancel();
    debounce = null;
    rebuilding = false;
    if (startupChanges) {
      activeRebuild = rebuild();
      await activeRebuild;
      if (done.isCompleted) return await done.future;
    }
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
