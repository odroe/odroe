import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:odroe/router_compiler.dart';

Future<void> main(List<String> arguments) async {
  final routes = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this command help.',
    )
    ..addFlag(
      'watch',
      abbr: 'w',
      negatable: false,
      help: 'Recompile when lib/routes changes.',
    )
    ..addOption(
      'project',
      defaultsTo: '.',
      help: 'Dart or Flutter application root.',
    )
    ..addOption(
      'routes',
      defaultsTo: 'lib/routes',
      help: 'Routes directory relative to the project root.',
    )
    ..addOption(
      'output',
      defaultsTo: 'lib/routes.dart',
      help: 'Generated file relative to the project root.',
    );
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show command help.')
    ..addCommand('routes', routes);

  late final ArgResults result;
  try {
    result = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage(parser));
    exitCode = 64;
    return;
  }

  final command = result.command;
  if (result.flag('help')) {
    stdout.writeln(_usage(parser));
    return;
  }
  if (command == null || command.name != 'routes') {
    stdout.writeln(_usage(parser));
    return;
  }
  if (command.flag('help')) {
    stdout.writeln(_routesUsage(routes));
    return;
  }

  final compiler = FileRouteCompiler(
    projectRoot: Directory(command.option('project')!),
    routesPath: command.option('routes')!,
    outputPath: command.option('output')!,
  );
  if (!_compile(compiler)) {
    exitCode = 1;
    if (!command.flag('watch')) return;
  }
  if (!command.flag('watch')) return;

  if (!compiler.routesDirectory.existsSync()) {
    stderr.writeln('${compiler.routesDirectory.path} does not exist.');
    exitCode = 1;
    return;
  }

  stdout.writeln('Watching ${compiler.routesDirectory.path}');
  Timer? debounce;
  await for (final event in compiler.routesDirectory.watch(recursive: true)) {
    if (File(event.path).absolute.path == compiler.outputFile.absolute.path) {
      continue;
    }
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 80), () {
      exitCode = _compile(compiler) ? 0 : 1;
    });
  }
}

bool _compile(FileRouteCompiler compiler) {
  try {
    final output = compiler.write();
    final path = compiler.outputFile.absolute.path;
    stdout.writeln(
      output.changed
          ? 'Generated $path (${output.routeCount} routes).'
          : 'Routes unchanged (${output.routeCount} routes).',
    );
    return true;
  } on FileRouteCompilationException catch (error) {
    for (final diagnostic in error.diagnostics) {
      stderr.writeln(diagnostic);
    }
    return false;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    return false;
  }
}

String _usage(ArgParser parser) =>
    'Usage: dart run odroe <command> [arguments]\n\n${parser.usage}';

String _routesUsage(ArgParser routes) =>
    'Usage: dart run odroe routes [arguments]\n\n${routes.usage}';
