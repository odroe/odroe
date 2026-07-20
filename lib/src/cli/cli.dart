import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:odroe/src/router_compiler/compiler.dart';

import 'build.dart';
import 'development.dart';
import 'project.dart';

/// Runs the Odroe command-line product and returns a process exit code.
Future<int> runOdroe(
  List<String> arguments, {
  StringSink? output,
  StringSink? errors,
}) async {
  final out = output ?? stdout;
  final err = errors ?? stderr;
  final generate = _generationParser()
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
      help: 'Run the Odroe server without starting flutter run.',
    );
  final build = _generationParser()
    ..addFlag(
      'server-only',
      negatable: false,
      help: 'Build only the Odroe server.',
    )
    ..addFlag(
      'server',
      defaultsTo: true,
      help: 'Build the Odroe server artifact.',
    )
    ..addOption(
      'server-artifact',
      defaultsTo: 'build/odroe/server',
      help: 'Server executable path relative to the project.',
    )
    ..addFlag(
      'prerender',
      defaultsTo: true,
      help: 'Generate static HTML for web and document-only builds.',
    )
    ..addOption(
      'prerender-output',
      defaultsTo: 'build/web',
      help: 'Static output directory relative to the project.',
    )
    ..addOption(
      'prerender-concurrency',
      defaultsTo: '${Platform.numberOfProcessors}',
      help: 'Maximum parallel prerender requests.',
    );
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('generate', generate)
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
        _parserFor(command.name!, generate, dev, build),
      ),
    );
    return 0;
  }

  try {
    final project = CliProject.from(command);
    return switch (command.name) {
      'generate' =>
        command.flag('watch')
            ? await _watchRoutes(project, out, err)
            : (generateRoutes(project, out, err) == null ? 1 : 0),
      'dev' => await runDevelopment(
        project,
        host: command.option('host')!,
        port: _port(command.option('port')!),
        serverOnly: command.flag('server-only'),
        flutterArguments: command.rest,
        out: out,
        err: err,
      ),
      'build' => await runBuild(
        project,
        serverOnly: command.flag('server-only'),
        buildServer: command.flag('server'),
        serverArtifact: command.option('server-artifact')!,
        prerender: command.flag('prerender'),
        prerenderOutput: command.option('prerender-output')!,
        prerenderConcurrency: _positiveInt(
          command.option('prerender-concurrency')!,
          'prerender-concurrency',
        ),
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
  } on ProcessException catch (error) {
    err.writeln(error.message);
    return error.errorCode == 0 ? 1 : error.errorCode;
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
  ArgParser dev,
  ArgParser build,
) => switch (name) {
  'generate' => generate,
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

int _positiveInt(String value, String name) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    throw FormatException('Invalid $name: $value');
  }
  return parsed;
}

Future<int> _watchRoutes(
  CliProject project,
  StringSink out,
  StringSink err,
) async {
  final generated = generateRoutes(project, out, err);
  if (generated == null) return 1;
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
      () => generateRoutes(project, out, err),
    );
  }
  return 0;
}

String _usage(ArgParser parser) =>
    'Usage: dart run odroe <command> [arguments]\n\n'
    'Commands:\n'
    '  generate  Generate client and server route targets.\n'
    '  dev       Watch source, run Odroe, and run Flutter.\n'
    '  build     Build a Flutter target and the Odroe server.\n'
    '${parser.usage}\n\n'
    'Flutter arguments and options follow --. A build target without options '
    'may be passed directly, for example: odroe build apk.';

String _commandUsage(String name, ArgParser parser) =>
    'Usage: dart run odroe $name [arguments]\n\n${parser.usage}';
