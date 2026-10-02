import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'project.dart';

/// Process launcher used by controlled CLI startup regressions.
typedef NativeDevelopmentProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      required CliProject project,
      Map<String, String>? environment,
    });

/// Runs the generated server and optional Flutter development process.
Future<int> runDevelopment(
  CliProject project, {
  required String host,
  required int port,
  required bool serverOnly,
  required List<String> flutterArguments,
  required String? sqliteMigrations,
  required StringSink out,
  required StringSink err,
  NativeDevelopmentProcessStarter processStarter = startProjectProcess,
}) async {
  final inheritedMigrations = Platform.environment['ODROE_MIGRATIONS_PATH'];
  if (sqliteMigrations == null && inheritedMigrations == '') {
    throw const FormatException('ODROE_MIGRATIONS_PATH must not be empty.');
  }
  final configuredMigrations = sqliteMigrations == null
      ? inheritedMigrations ?? project.configuredSqliteMigrations
      : resolveProjectPath(
          project.root,
          sqliteMigrations,
          option: '--sqlite-migrations',
        );
  final migrationsDirectory = configuredMigrations == null
      ? null
      : Directory(
          p.isAbsolute(configuredMigrations)
              ? configuredMigrations
              : p.join(project.root.path, configuredMigrations),
        ).absolute;
  final done = Completer<int>();
  var startupChanged = false;
  var startupServerRestartNeeded = false;
  void Function({required bool server})? dispatchSourceChange;
  final sourceWatcher = DirectoryWatcher(project.libDirectory.path);
  final sourceChanges = sourceWatcher.events.listen(
    (event) {
      if (done.isCompleted || !event.path.endsWith('.dart')) return;
      if (p.equals(event.path, project.compiler.outputFile.path) ||
          p.equals(event.path, project.compiler.serverOutputFile.path)) {
        return;
      }
      final name = p.basename(event.path);
      final flutterOnlyModification =
          event.type == ChangeType.MODIFY &&
          p.isWithin(project.compiler.routesDirectory.path, event.path) &&
          (name == 'page.dart' || name == 'shell.dart');
      final dispatch = dispatchSourceChange;
      if (dispatch == null) {
        startupChanged = true;
        startupServerRestartNeeded |= !flutterOnlyModification;
      } else {
        dispatch(server: !flutterOnlyModification);
      }
    },
    onError: (Object error) {
      err.writeln('Source watcher failed. $error');
      if (!done.isCompleted) done.complete(1);
    },
  );

  try {
    // Subscribe before the first generation or child launch. Until startup
    // finishes, changes coalesce into one regeneration/restart request.
    await sourceWatcher.ready;
    if (done.isCompleted) return await done.future;
    final generated = generateRoutes(project, out, err);
    if (generated == null) return 1;
    final resolvedPort = port == 0 ? await _availablePort(host) : port;
    final device = _deviceId(flutterArguments);
    final webDevice = _webDevices.contains(device);
    File? developmentOriginFile;
    var resolvedFlutterArguments = flutterArguments;
    if (!serverOnly && generated.hasFlutter && webDevice) {
      final flutterHost =
          _optionValue(flutterArguments, 'web-hostname') ?? '127.0.0.1';
      final configuredFlutterPortValue = _optionValue(
        flutterArguments,
        'web-port',
      );
      final configuredFlutterPort = configuredFlutterPortValue == null
          ? null
          : int.tryParse(configuredFlutterPortValue);
      if (configuredFlutterPortValue != null &&
          (configuredFlutterPort == null ||
              configuredFlutterPort <= 0 ||
              configuredFlutterPort > 65535)) {
        throw FormatException('Invalid web-port: $configuredFlutterPortValue');
      }
      final flutterPort =
          configuredFlutterPort ?? await _availablePort(flutterHost);
      final launchHost = _loopbackHost(host);
      final launch = Uri(scheme: 'http', host: launchHost, port: resolvedPort);
      resolvedFlutterArguments = <String>[
        ...flutterArguments,
        if (!_hasOption(flutterArguments, 'web-hostname'))
          '--web-hostname=$flutterHost',
        if (!_hasOption(flutterArguments, 'web-port'))
          '--web-port=$flutterPort',
        if (device != 'web-server' &&
            !_hasOption(flutterArguments, 'web-launch-url'))
          '--web-launch-url=$launch',
        if (!_hasOption(flutterArguments, 'web-server-debug-protocol'))
          '--web-server-debug-protocol=sse',
        if (!_hasOption(flutterArguments, 'web-server-debug-backend-protocol'))
          '--web-server-debug-backend-protocol=sse',
        if (!_hasOption(
          flutterArguments,
          'web-server-debug-injected-client-protocol',
        ))
          '--web-server-debug-injected-client-protocol=sse',
      ];
      developmentOriginFile = File(
        p.join(project.root.path, '.dart_tool', 'odroe', 'flutter_origin'),
      );
      developmentOriginFile.parent.createSync(recursive: true);
      developmentOriginFile.writeAsStringSync(
        Uri(
          scheme: 'http',
          host: _loopbackHost(flutterHost),
          port: flutterPort,
        ).toString(),
      );
    }
    final publicDirectory = Directory(p.join(project.root.path, 'public'));
    final environment = <String, String>{
      ...Platform.environment,
      'ODROE_HOST': host,
      'ODROE_PORT': '$resolvedPort',
      'ODROE_WEB_ROOT': publicDirectory.existsSync()
          ? publicDirectory.path
          : '',
      'ODROE_FLUTTER_ORIGIN_FILE': developmentOriginFile?.path ?? '',
      if (migrationsDirectory != null)
        'ODROE_MIGRATIONS_PATH': migrationsDirectory.path,
    };
    Process server = await processStarter(
      Platform.resolvedExecutable,
      <String>['run', project.bootstrap.path],
      project: project,
      environment: environment,
    );
    Process? flutter;
    if (!serverOnly && generated.hasFlutter) {
      try {
        flutter = await processStarter('flutter', <String>[
          'run',
          ...resolvedFlutterArguments,
        ], project: project);
      } on Object {
        await _terminateNativeProcess(server, err);
        if (developmentOriginFile?.existsSync() ?? false) {
          developmentOriginFile!.deleteSync();
        }
        rethrow;
      }
    }

    var stopping = false;
    var restarting = false;
    void observeServer(Process process) {
      process.exitCode.then((code) {
        if (!stopping && !restarting && !done.isCompleted) done.complete(code);
      });
    }

    observeServer(server);
    flutter?.exitCode.then((code) {
      if (!stopping && !done.isCompleted) done.complete(code);
    });

    Timer? debounce;
    var serverRestartNeeded = false;
    var restartQueued = false;
    Future<void> restart() async {
      if (stopping) return;
      if (restarting) {
        restartQueued = true;
        return;
      }
      restarting = true;
      try {
        do {
          restartQueued = false;
          final shouldRestartServer = serverRestartNeeded;
          serverRestartNeeded = false;
          final generated = generateRoutes(project, out, err);
          if (generated == null || !shouldRestartServer) continue;

          server.kill(ProcessSignal.sigterm);
          await server.exitCode;
          if (stopping) break;
          final nextServer = await processStarter(
            Platform.resolvedExecutable,
            <String>['run', project.bootstrap.path],
            project: project,
            environment: environment,
          );
          if (stopping) {
            await _terminateNativeProcess(nextServer, err);
            break;
          }
          server = nextServer;
          observeServer(server);
        } while (restartQueued && !stopping);
      } finally {
        restarting = false;
      }
    }

    Future<void>? restartFuture;
    void queueRestart({required bool server}) {
      serverRestartNeeded |= server;
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 120), () {
        if (restartFuture != null) {
          restartQueued = true;
          return;
        }
        late final Future<void> trackedRestart;
        trackedRestart = restart()
            .catchError((Object error, StackTrace stackTrace) {
              err.writeln(error);
              if (!done.isCompleted) done.complete(1);
            })
            .whenComplete(() {
              if (identical(restartFuture, trackedRestart)) {
                restartFuture = null;
              }
            });
        restartFuture = trackedRestart;
        unawaited(trackedRestart);
      });
    }

    final changes = <StreamSubscription<Object>>[];
    dispatchSourceChange = queueRestart;
    if (startupChanged) {
      queueRestart(server: startupServerRestartNeeded);
    }
    if (migrationsDirectory?.existsSync() ?? false) {
      changes.add(
        migrationsDirectory!.watch().listen((event) {
          if (event.path.endsWith('.sql')) queueRestart(server: true);
        }),
      );
    }

    final signals = <StreamSubscription<ProcessSignal>>[];
    void stop(ProcessSignal _) {
      if (done.isCompleted) return;
      stopping = true;
      done.complete(0);
    }

    if (!Platform.isWindows) {
      signals.add(ProcessSignal.sigint.watch().listen(stop));
      signals.add(ProcessSignal.sigterm.watch().listen(stop));
    }
    final result = await done.future;
    stopping = true;
    debounce?.cancel();
    for (final change in changes) {
      await change.cancel();
    }
    for (final signal in signals) {
      await signal.cancel();
    }
    // A restart may already be awaiting this server's graceful drain. Stop
    // children with escalation before joining it, so active work cannot keep
    // the development CLI and its children alive indefinitely.
    final pendingRestart = restartFuture;
    await Future.wait<void>(<Future<void>>[
      _terminateNativeProcess(server, err),
      if (flutter != null) _terminateNativeProcess(flutter, err),
    ]);
    if (pendingRestart != null) {
      try {
        await pendingRestart.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        err.writeln(
          'Native development restart did not stop within 5 seconds.',
        );
      }
    }
    if (developmentOriginFile?.existsSync() ?? false) {
      developmentOriginFile!.deleteSync();
    }
    return result;
  } finally {
    dispatchSourceChange = null;
    await sourceChanges.cancel();
  }
}

Future<void> _terminateNativeProcess(Process process, StringSink err) async {
  final exitCode = process.exitCode;
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
    err.writeln(
      'Native development child ${process.pid} did not exit after SIGKILL.',
    );
  }
}

Future<int> _availablePort(String host) async {
  final socket = await ServerSocket.bind(host, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

String _loopbackHost(String host) =>
    host == '0.0.0.0' || host == '::' ? '127.0.0.1' : host;

String? _deviceId(List<String> arguments) {
  for (var index = 0; index < arguments.length; index++) {
    final value = arguments[index];
    if ((value == '-d' || value == '--device-id') &&
        index + 1 < arguments.length) {
      return arguments[index + 1].toLowerCase();
    }
    if (value.startsWith('--device-id=')) {
      return value.substring('--device-id='.length).toLowerCase();
    }
    if (value.startsWith('-d') && value.length > 2) {
      return value.substring(2).toLowerCase();
    }
  }
  return null;
}

bool _hasOption(List<String> arguments, String name) =>
    _optionValue(arguments, name) != null;

String? _optionValue(List<String> arguments, String name) {
  final long = '--$name';
  for (var index = 0; index < arguments.length; index++) {
    final value = arguments[index];
    if (value == long && index + 1 < arguments.length) {
      return arguments[index + 1];
    }
    if (value.startsWith('$long=')) return value.substring(long.length + 1);
  }
  return null;
}

const Set<String> _webDevices = <String>{
  'chrome',
  'edge',
  'firefox',
  'web-server',
};
