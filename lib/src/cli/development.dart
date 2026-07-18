// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'project.dart';

Future<int> runDevelopment(
  CliProject project, {
  required String host,
  required int port,
  required bool serverOnly,
  required List<String> flutterArguments,
  required StringSink out,
  required StringSink err,
}) async {
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
      if (!_hasOption(flutterArguments, 'web-port')) '--web-port=$flutterPort',
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
  final environment = <String, String>{
    ...Platform.environment,
    'ODROE_HOST': host,
    'ODROE_PORT': '$resolvedPort',
    if (developmentOriginFile != null) ...<String, String>{
      'ODROE_FLUTTER_ORIGIN_FILE': developmentOriginFile.path,
      'ODROE_WEB_ROOT': '',
    },
  };
  Process server = await startProjectProcess(
    Platform.resolvedExecutable,
    <String>['run', project.bootstrap.path],
    project: project,
    environment: environment,
  );
  Process? flutter;
  if (!serverOnly && generated.hasFlutter) {
    try {
      flutter = await startProjectProcess('flutter', <String>[
        'run',
        ...resolvedFlutterArguments,
      ], project: project);
    } on Object {
      server.kill(ProcessSignal.sigterm);
      await server.exitCode;
      if (developmentOriginFile?.existsSync() ?? false) {
        developmentOriginFile!.deleteSync();
      }
      rethrow;
    }
  }

  final done = Completer<int>();
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
        server = await startProjectProcess(
          Platform.resolvedExecutable,
          <String>['run', project.bootstrap.path],
          project: project,
          environment: environment,
        );
        observeServer(server);
      } while (restartQueued && !stopping);
    } finally {
      restarting = false;
    }
  }

  final changes = project.libDirectory.watch(recursive: true).listen((event) {
    if (!event.path.endsWith('.dart')) return;
    if (p.equals(event.path, project.compiler.outputFile.path) ||
        p.equals(event.path, project.compiler.serverOutputFile.path)) {
      return;
    }
    final name = p.basename(event.path);
    final flutterOnlyModification =
        event.type == FileSystemEvent.modify &&
        (name == 'page.dart' || name == 'shell.dart');
    serverRestartNeeded |= !flutterOnlyModification;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 120), () {
      unawaited(
        restart().catchError((Object error, StackTrace stackTrace) {
          err.writeln(error);
          if (!done.isCompleted) done.complete(1);
        }),
      );
    });
  });

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
  await changes.cancel();
  for (final signal in signals) {
    await signal.cancel();
  }
  server.kill(ProcessSignal.sigterm);
  flutter?.kill(ProcessSignal.sigterm);
  await Future.wait<void>(<Future<void>>[
    server.exitCode.then<void>((_) {}),
    if (flutter != null) flutter.exitCode.then<void>((_) {}),
  ]);
  if (developmentOriginFile?.existsSync() ?? false) {
    developmentOriginFile!.deleteSync();
  }
  return result;
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
