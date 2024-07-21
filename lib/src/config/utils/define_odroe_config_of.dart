import 'dart:io';

import 'package:path/path.dart' as path;

import '../odroe_config.dart';
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
}
