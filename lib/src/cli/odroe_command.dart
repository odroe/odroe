import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as path;
import 'package:odroe/config.dart';

import '../_internal/context.dart';
import 'utils/find_project_root.dart';
import 'utils/generate_cached_config_file.dart';

abstract class OdroeCommand extends Command {
  Directory? _root;
  Context? _context;

  Directory get root => _root ??= switch (globalResults?.option('root')) {
        String root => _resolveRootDirectory(root),
        _ => findProjectRoot(Directory.current),
      };

  String get config {
    return switch (globalResults?.option('config')) {
      String path => path,
      _ => 'odroe.config.dart',
    };
  }

  OdroeMode get defaultMode => OdroeMode.development;

  OdroeMode get mode {
    return switch (globalResults?.option('mode')) {
      String name => OdroeMode.values.firstWhere((e) => e.name == name),
      _ => defaultMode,
    };
  }

  Context get context => _context ??= Context(root.path);

  @override
  run() async {
    await generateCachedConfigFile(
      context,
      configFile: config,
      mode: mode,
    );
  }

  Directory _resolveRootDirectory(String root) {
    root = path.canonicalize(root);
    final pubspec = File(path.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      usageException('The root directory not is a project root dir.');
    }

    return Directory(root).absolute;
  }
}
