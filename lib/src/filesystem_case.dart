import 'dart:io';

import 'package:path/path.dart' as p;

/// Reports whether the existing volume aliases ASCII path case.
bool usesCaseInsensitivePaths(String path) {
  if (Platform.isWindows) return true;

  var directory = p.normalize(Directory(path).absolute.path);
  while (FileSystemEntity.typeSync(directory) !=
      FileSystemEntityType.directory) {
    final parent = p.dirname(directory);
    if (p.equals(parent, directory)) return true;
    directory = parent;
  }
  while (true) {
    final name = p.basename(directory);
    final alternateName = _toggleAsciiCase(name);
    if (alternateName != name) {
      final alternate = p.join(p.dirname(directory), alternateName);
      if (FileSystemEntity.typeSync(alternate) ==
          FileSystemEntityType.notFound) {
        return false;
      }
      try {
        return FileSystemEntity.identicalSync(directory, alternate);
      } on FileSystemException {
        return true;
      }
    }
    final parent = p.dirname(directory);
    if (p.equals(parent, directory)) return true;
    directory = parent;
  }
}

String _toggleAsciiCase(String value) {
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0x41 && unit <= 0x5a) {
      return '${value.substring(0, index)}'
          '${String.fromCharCode(unit + 0x20)}${value.substring(index + 1)}';
    }
    if (unit >= 0x61 && unit <= 0x7a) {
      return '${value.substring(0, index)}'
          '${String.fromCharCode(unit - 0x20)}${value.substring(index + 1)}';
    }
  }
  return value;
}
