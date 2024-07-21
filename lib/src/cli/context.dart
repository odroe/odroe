import 'package:path/path.dart' as path;

class Context {
  Context(this.root);

  final String root;

  String get cachePath => path.join(root, '.odroe');
  String get configPath => path.join(cachePath, 'config.dart');
  String get buildCommandPath => path.join(cachePath, 'commands', 'build.dart');
  String get devCommandPath => path.join(cachePath, 'commands', 'dev.dart');
}
