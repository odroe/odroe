import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:odroe/config.dart';

import 'commands/build_command.dart';
import 'commands/dev_command.dart';
import 'utils/find_project_root.dart';

runOdroeCLI(Iterable<String> args) {
  final runner = CommandRunner(
      'odroe', '🫧 Odroe Generation CLI Experience (odroe v0.1.0-dev)');

  runner.argParser
    ..addOption('root',
        help: 'Project root directory.',
        valueHelp: 'directory',
        defaultsTo: findProjectRoot(Directory.current).path)
    ..addOption('config',
        abbr: 'c',
        help: 'Use specified config file.',
        valueHelp: 'file',
        defaultsTo: 'odroe.config.dart')
    ..addOption('mode',
        abbr: 'm',
        allowed: OdroeMode.values.map((e) => e.name),
        help: 'Override the default mode for both dev and build.');
  runner
    ..addCommand(BuildCommand())
    ..addCommand(DevCommand());

  return runner.run(args);
}
