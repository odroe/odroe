import 'dart:io';

import 'package:path/path.dart' as path;

Directory findProjectRoot(Directory dir) {
  final pubspec = File(path.join(dir.path, 'pubspec.yaml'));
  if (pubspec.existsSync()) return dir.absolute;

  // The dir is system root.
  if (dir.path == path.rootPrefix(dir.path) || dir.parent.path == dir.path) {
    const error = OSError('Not found project directory.');
    throw PathNotFoundException(pubspec.path, error);
  }

  return findProjectRoot(dir.parent);
}
