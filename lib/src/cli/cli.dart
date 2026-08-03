import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:odroe/server_io.dart';
import 'package:odroe/src/router_compiler/compiler.dart';

import 'build.dart';
import 'cloudflare_development.dart';
import 'create.dart';
import 'development.dart';
import 'initialize.dart';
import 'project.dart';

/// Runs the Odroe command-line product and returns a process exit code.
Future<int> runOdroe(
  List<String> arguments, {
  StringSink? output,
  StringSink? errors,
  CreateCommandRunner? createCommandRunner,
}) async {
  final out = output ?? stdout;
  final err = errors ?? stderr;
  final init = _projectParser()
    ..addFlag(
      'full-stack',
      negatable: false,
      help: 'Create a Query, RPC, typed SQL, SQLite, and Cloudflare starter.',
    );
  final generate = _generationParser()
    ..addFlag(
      'watch',
      abbr: 'w',
      negatable: false,
      help: 'Recompile when route files change.',
    );
  final create = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption(
      'platforms',
      defaultsTo: 'android,ios,web',
      help: 'Comma-separated Flutter platforms.',
    )
    ..addOption('org', help: 'Reverse-domain organization identifier.')
    ..addOption('project-name', help: 'Dart package name for the project.')
    ..addOption(
      'odroe-path',
      help: 'Odroe package checkout to use as a path dependency.',
    )
    ..addFlag(
      'offline',
      negatable: false,
      help: 'Resolve the Odroe dependency from the local package cache.',
    );
  final dev = _generationParser()
    ..addOption('host', defaultsTo: '127.0.0.1')
    ..addOption('port', defaultsTo: '3000')
    ..addOption(
      'server-target',
      allowed: ServerBuildTarget.values.map((target) => target.name),
      defaultsTo: ServerBuildTarget.native.name,
      help: 'Server runtime to run.',
    )
    ..addOption(
      'sqlite-migrations',
      help: 'SQLite migration directory relative to the project.',
    )
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
      help: 'Emit a deployable Odroe server artifact.',
    )
    ..addOption(
      'server-artifact',
      help: 'Native bundle or Cloudflare JS path inside the build directory.',
    )
    ..addOption(
      'server-target',
      allowed: ServerBuildTarget.values.map((target) => target.name),
      defaultsTo: ServerBuildTarget.native.name,
      help: 'Server runtime to compile.',
    )
    ..addOption(
      'sqlite-migrations',
      help: 'Use this SQLite source for Native bundle and prerender.',
    )
    ..addFlag(
      'prerender',
      defaultsTo: true,
      help: 'Generate static HTML for web and document-only builds.',
    )
    ..addOption(
      'prerender-output',
      defaultsTo: 'build/web',
      help: 'Static output directory inside the project build directory.',
    )
    ..addOption(
      'prerender-concurrency',
      defaultsTo: '${Prerenderer.defaultConcurrency}',
      help: 'Maximum parallel prerender requests.',
    )
    ..addFlag(
      'prerender-crawl',
      negatable: false,
      help: 'Discover additional same-origin HTML links.',
    )
    ..addOption(
      'prerender-max-routes',
      defaultsTo: '${Prerenderer.defaultMaxRoutes}',
      help: 'Maximum explicit and discovered prerender routes.',
    )
    ..addOption(
      'prerender-max-response-bytes',
      defaultsTo: '${Prerenderer.defaultMaxResponseBytes}',
      help: 'Maximum HTML response bytes per prerender route.',
    );
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('create', create)
    ..addCommand('init', init)
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
        _parserFor(command.name!, create, init, generate, dev, build),
      ),
    );
    return 0;
  }

  try {
    if (command.name == 'create') {
      if (command.rest.length != 1) {
        err.writeln('odroe create requires exactly one target directory.');
        return 64;
      }
      await createProject(
        directory: command.rest.single,
        odroePath: command.option('odroe-path'),
        platforms: command.option('platforms')!,
        organization: command.option('org'),
        projectName: command.option('project-name'),
        offline: command.flag('offline'),
        out: out,
        err: err,
        runCommand: createCommandRunner,
      );
      return 0;
    }
    if (command.name == 'init' && command.rest.isNotEmpty) {
      err.writeln('odroe init does not accept positional arguments.');
      return 64;
    }
    final project = command.name == 'init'
        ? CliProject.fromRoot(command.option('project')!)
        : CliProject.from(command);
    return switch (command.name) {
      'init' =>
        initializeProject(
              project,
              out,
              err,
              fullStack: command.flag('full-stack'),
            )
            ? 0
            : 1,
      'generate' =>
        command.flag('watch')
            ? await _watchRoutes(project, out, err)
            : (generateRoutes(project, out, err) == null ? 1 : 0),
      'dev' => await _runDevelopmentCommand(project, command, out, err),
      'build' => await runBuild(
        project,
        serverOnly: command.flag('server-only'),
        buildServer: command.flag('server'),
        serverTarget: ServerBuildTarget.values.byName(
          command.option('server-target')!,
        ),
        serverArtifact: command.option('server-artifact'),
        sqliteMigrations: command.option('sqlite-migrations'),
        prerender: command.flag('prerender'),
        prerenderOutput: command.option('prerender-output')!,
        prerenderConcurrency: _positiveInt(
          command.option('prerender-concurrency')!,
          'prerender-concurrency',
        ),
        prerenderCrawl: command.flag('prerender-crawl'),
        prerenderMaxRoutes: _positiveInt(
          command.option('prerender-max-routes')!,
          'prerender-max-routes',
        ),
        prerenderMaxResponseBytes: _positiveInt(
          command.option('prerender-max-response-bytes')!,
          'prerender-max-response-bytes',
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

Future<int> _runDevelopmentCommand(
  CliProject project,
  ArgResults command,
  StringSink out,
  StringSink err,
) {
  final target = ServerBuildTarget.values.byName(
    command.option('server-target')!,
  );
  if (target == ServerBuildTarget.cloudflare &&
      command.option('sqlite-migrations') != null) {
    throw const FormatException(
      '--sqlite-migrations is only available in Native development.',
    );
  }
  final arguments = (
    host: command.option('host')!,
    port: _port(command.option('port')!),
    serverOnly: command.flag('server-only'),
    flutterArguments: command.rest,
  );
  return switch (target) {
    ServerBuildTarget.native => runDevelopment(
      project,
      host: arguments.host,
      port: arguments.port,
      serverOnly: arguments.serverOnly,
      flutterArguments: arguments.flutterArguments,
      sqliteMigrations: command.option('sqlite-migrations'),
      out: out,
      err: err,
    ),
    ServerBuildTarget.cloudflare => runCloudflareDevelopment(
      project,
      host: arguments.host,
      port: arguments.port,
      serverOnly: arguments.serverOnly,
      flutterArguments: arguments.flutterArguments,
      out: out,
      err: err,
    ),
  };
}

ArgParser _projectParser() => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false)
  ..addOption(
    'project',
    defaultsTo: '.',
    help: 'Dart or Flutter application root.',
  );

ArgParser _generationParser() => _projectParser()
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
  ArgParser create,
  ArgParser init,
  ArgParser generate,
  ArgParser dev,
  ArgParser build,
) => switch (name) {
  'create' => create,
  'init' => init,
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
    '  create    Create a new full-stack Flutter application.\n'
    '  init      Initialize an empty Flutter application.\n'
    '  generate  Generate client and server route targets.\n'
    '  dev       Watch source, run Odroe, and run Flutter.\n'
    '  build     Build a Flutter target and the Odroe server.\n'
    '${parser.usage}\n\n'
    'Flutter arguments and options follow --. A build target without options '
    'may be passed directly, for example: odroe build apk.';

String _commandUsage(String name, ArgParser parser) =>
    'Usage: dart run odroe $name [arguments]\n\n${parser.usage}';
