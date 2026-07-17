import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:odroe/router_compiler.dart';
import 'package:path/path.dart' as p;

/// Runs the Odroe command-line product and returns a process exit code.
Future<int> runOdroe(
  List<String> arguments, {
  StringSink? output,
  StringSink? errors,
}) async {
  final out = output ?? stdout;
  final err = errors ?? stderr;
  final shared = _generationParser();
  final routes = _generationParser()
    ..addFlag(
      'watch',
      abbr: 'w',
      negatable: false,
      help: 'Recompile when route files change.',
    );
  final dev = _generationParser()
    ..addOption('host', defaultsTo: '127.0.0.1')
    ..addOption('port', defaultsTo: '3000')
    ..addFlag(
      'server-only',
      negatable: false,
      help: 'Run Start without starting flutter run.',
    );
  final build = _generationParser()
    ..addFlag(
      'server-only',
      negatable: false,
      help: 'Build only the Start server.',
    )
    ..addFlag(
      'server',
      defaultsTo: true,
      help: 'Build the Start server artifact.',
    )
    ..addOption(
      'server-artifact',
      defaultsTo: 'build/odroe/server',
      help: 'Server executable path relative to the project.',
    );
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('generate', shared)
    ..addCommand('routes', routes)
    ..addCommand('dev', dev)
    ..addCommand('build', build);

  late final ArgResults result;
  try {
    result = parser.parse(arguments);
  } on FormatException catch (error) {
    err.writeln(error.message);
    err.writeln(_usage(parser));
    return 64;
  }
  if (result.flag('help') || result.command == null) {
    out.writeln(_usage(parser));
    return 0;
  }
  final command = result.command!;
  if (command.flag('help')) {
    out.writeln(
      _commandUsage(
        command.name!,
        _parserFor(command.name!, shared, routes, dev, build),
      ),
    );
    return 0;
  }

  try {
    final project = _Project.from(command);
    return switch (command.name) {
      'generate' => _generate(project, out, err) ? 0 : 1,
      'routes' =>
        command.flag('watch')
            ? await _watchRoutes(project, out, err)
            : (_generate(project, out, err) ? 0 : 1),
      'dev' => await _dev(
        project,
        host: command.option('host')!,
        port: _port(command.option('port')!),
        serverOnly: command.flag('server-only'),
        flutterArguments: command.rest,
        out: out,
        err: err,
      ),
      'build' => await _build(
        project,
        serverOnly: command.flag('server-only'),
        buildServer: command.flag('server'),
        serverArtifact: command.option('server-artifact')!,
        flutterArguments: command.rest,
        out: out,
        err: err,
      ),
      _ => 64,
    };
  } on FileRouteCompilationException catch (error) {
    for (final diagnostic in error.diagnostics) {
      err.writeln(diagnostic);
    }
    return 1;
  } on FormatException catch (error) {
    err.writeln(error.message);
    return 64;
  } on FileSystemException catch (error) {
    err.writeln(error.message);
    return 1;
  }
}

ArgParser _generationParser() => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false)
  ..addOption(
    'project',
    defaultsTo: '.',
    help: 'Dart or Flutter application root.',
  )
  ..addOption(
    'routes',
    defaultsTo: 'lib/routes',
    help: 'Routes directory relative to the project.',
  )
  ..addOption(
    'output',
    defaultsTo: 'lib/routes.dart',
    help: 'Client-safe output relative to the project.',
  )
  ..addOption(
    'server-output',
    defaultsTo: 'lib/routes.server.dart',
    help: 'Server-only output relative to the project.',
  );

ArgParser _parserFor(
  String name,
  ArgParser generate,
  ArgParser routes,
  ArgParser dev,
  ArgParser build,
) => switch (name) {
  'generate' => generate,
  'routes' => routes,
  'dev' => dev,
  'build' => build,
  _ => ArgParser(),
};

int _port(String value) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0 || parsed > 65535) {
    throw FormatException('Invalid port: $value');
  }
  return parsed;
}

bool _generate(_Project project, StringSink out, StringSink err) {
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
    return true;
  } on FileRouteCompilationException catch (error) {
    for (final diagnostic in error.diagnostics) {
      err.writeln(diagnostic);
    }
    return false;
  }
}

Future<int> _watchRoutes(
  _Project project,
  StringSink out,
  StringSink err,
) async {
  if (!_generate(project, out, err)) return 1;
  if (!project.compiler.routesDirectory.existsSync()) {
    err.writeln('${project.compiler.routesDirectory.path} does not exist.');
    return 1;
  }
  out.writeln('Watching ${project.compiler.routesDirectory.path}');
  Timer? debounce;
  await for (final event in project.compiler.routesDirectory.watch(
    recursive: true,
  )) {
    if (!event.path.endsWith('.dart')) continue;
    debounce?.cancel();
    debounce = Timer(
      const Duration(milliseconds: 100),
      () => _generate(project, out, err),
    );
  }
  return 0;
}

Future<int> _dev(
  _Project project, {
  required String host,
  required int port,
  required bool serverOnly,
  required List<String> flutterArguments,
  required StringSink out,
  required StringSink err,
}) async {
  if (!_generate(project, out, err)) return 1;
  final environment = <String, String>{
    ...Platform.environment,
    'ODROE_HOST': host,
    'ODROE_PORT': '$port',
  };
  Process server = await _start(
    Platform.resolvedExecutable,
    <String>['run', project.bootstrap.path],
    project: project,
    environment: environment,
  );
  Process? flutter;
  if (!serverOnly) {
    flutter = await _start('flutter', <String>[
      'run',
      ...flutterArguments,
    ], project: project);
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
  FileSystemEvent? pendingEvent;
  final changes = project.libDirectory.watch(recursive: true).listen((event) {
    if (!event.path.endsWith('.dart')) return;
    if (p.equals(event.path, project.compiler.outputFile.path) ||
        p.equals(event.path, project.compiler.serverOutputFile.path)) {
      return;
    }
    pendingEvent = event;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 120), () async {
      if (stopping || restarting) return;
      restarting = true;
      final generated = _generate(project, out, err);
      final changed = pendingEvent;
      final name = changed == null ? '' : p.basename(changed.path);
      final flutterOnlyModification =
          changed?.type == FileSystemEvent.modify &&
          (name == 'page.dart' || name == 'shell.dart');
      if (!generated || flutterOnlyModification) {
        restarting = false;
        return;
      }
      server.kill(ProcessSignal.sigterm);
      await server.exitCode;
      if (!stopping) {
        server = await _start(
          Platform.resolvedExecutable,
          <String>['run', project.bootstrap.path],
          project: project,
          environment: environment,
        );
        restarting = false;
        observeServer(server);
      } else {
        restarting = false;
      }
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
  return result;
}

Future<int> _build(
  _Project project, {
  required bool serverOnly,
  required bool buildServer,
  required String serverArtifact,
  required List<String> flutterArguments,
  required StringSink out,
  required StringSink err,
}) async {
  if (!_generate(project, out, err)) return 1;
  if (serverOnly && !buildServer) {
    err.writeln('--server-only cannot be combined with --no-server.');
    return 64;
  }
  if (!serverOnly && flutterArguments.isEmpty) {
    err.writeln(
      'Choose a Flutter build target, for example: '
      'dart run odroe build apk or dart run odroe build web.',
    );
    return 64;
  }
  final processes = <Process>[];
  if (!serverOnly) {
    processes.add(
      await _start('flutter', <String>[
        'build',
        ...flutterArguments,
      ], project: project),
    );
  }
  if (buildServer) {
    final artifact = File(p.join(project.root.path, serverArtifact));
    artifact.parent.createSync(recursive: true);
    processes.add(
      await _start(Platform.resolvedExecutable, <String>[
        'compile',
        'exe',
        project.bootstrap.path,
        '-o',
        artifact.path,
      ], project: project),
    );
  }
  final codes = await Future.wait<int>(
    processes.map((process) => process.exitCode),
  );
  return codes.fold<int>(0, (result, code) => result == 0 ? code : result);
}

Future<Process> _start(
  String executable,
  List<String> arguments, {
  required _Project project,
  Map<String, String>? environment,
}) => Process.start(
  executable,
  arguments,
  workingDirectory: project.root.path,
  environment: environment,
  mode: ProcessStartMode.inheritStdio,
);

final class _Project {
  _Project._({
    required this.root,
    required this.packageName,
    required this.compiler,
  });

  factory _Project.from(ArgResults arguments) {
    final root = Directory(arguments.option('project')!).absolute;
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
    return _Project._(
      root: root,
      packageName: match.group(1)!,
      compiler: FileRouteCompiler(
        projectRoot: root,
        routesPath: arguments.option('routes')!,
        outputPath: arguments.option('output')!,
        serverOutputPath: arguments.option('server-output')!,
      ),
    );
  }

  final Directory root;
  final String packageName;
  final FileRouteCompiler compiler;

  Directory get libDirectory => Directory(p.join(root.path, 'lib'));
  File get bootstrap =>
      File(p.join(root.path, '.dart_tool', 'odroe', 'server.dart'));

  void writeBootstrap() {
    final source = _bootstrapSource(packageName);
    bootstrap.parent.createSync(recursive: true);
    if (bootstrap.existsSync() && bootstrap.readAsStringSync() == source) {
      return;
    }
    final temporary = File('${bootstrap.path}.tmp');
    try {
      temporary.writeAsStringSync(source);
      temporary.renameSync(bootstrap.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }
}

String _bootstrapSource(String packageName) =>
    '''
// Generated by Odroe. Do not edit.
import 'dart:async';
import 'dart:io';

import 'package:odroe/start_io.dart';
import 'package:$packageName/routes.server.dart';

Future<void> main() async {
  final host = Platform.environment['ODROE_HOST'] ?? '127.0.0.1';
  final port = int.parse(Platform.environment['ODROE_PORT'] ?? '3000');
  final server = await StartIoServer.bind(
    createStartApplication().handler,
    address: host,
    port: port,
  );
  stdout.writeln(
    'Odroe Start listening on http://\${server.address.host}:\${server.port}',
  );
  if (!Platform.isWindows) {
    final stopping = Completer<void>();
    void stop(ProcessSignal _) {
      if (!stopping.isCompleted) stopping.complete();
    }
    final interrupt = ProcessSignal.sigint.watch().listen(stop);
    final terminate = ProcessSignal.sigterm.watch().listen(stop);
    await stopping.future;
    await interrupt.cancel();
    await terminate.cancel();
    await server.close(force: true);
  }
}
''';

String _usage(ArgParser parser) =>
    'Usage: dart run odroe <command> [arguments]\n\n'
    'Commands:\n'
    '  generate  Generate client and server route targets.\n'
    '  dev       Watch source, run Start, and run Flutter.\n'
    '  build     Build a chosen Flutter target and Start server.\n'
    '  routes    Generate routes only, optionally watching.\n\n'
    '${parser.usage}\n\n'
    'Flutter arguments and options follow --. A build target without options '
    'may be passed directly, for example: odroe build apk.';

String _commandUsage(String name, ArgParser parser) =>
    'Usage: dart run odroe $name [arguments]\n\n${parser.usage}';
