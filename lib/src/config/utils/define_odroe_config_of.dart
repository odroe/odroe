import 'dart:io';

import 'package:path/path.dart' as path;

import '../env_options.dart';
import '../odroe_config.dart';
import '../server_options.dart';
import '../shared_options.dart';

OdroeConfig defineOdroeConfigOf({
  required Directory root,
  required OdroeMode mode,
}) {
  return _OdroeConfigImpl(root, mode);
}

class _OdroeConfigImpl extends OdroeConfig {
  _OdroeConfigImpl(this.root, this.mode);

  @override
  OdroeMode mode;

  @override
  Directory root;

  Directory? _routes;

  @override
  Directory get routes =>
      _routes ??= Directory(path.join(root.absolute.path, 'routes'));

  @override
  set routes(Directory directory) => _routes = directory;

  @override
  late final ServerOptions server = _ServerOptionsImpl();

  @override
  late final EnvOptions env = _EnvOptionsImpl(root);
}

class _EnvOptionsImpl extends EnvOptions {
  _EnvOptionsImpl(this.dir);

  @override
  Directory dir;
}

class _ServerOptionsImpl extends ServerOptions {}
