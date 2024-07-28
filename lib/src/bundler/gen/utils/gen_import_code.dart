import 'dart:io';

import 'package:path/path.dart' as p;

String genImportCode(Iterable<String> files, String target, String prefix) {
  final imports = <String>[];
  for (final (index, file) in files.indexed) {
    final buffer = StringBuffer('import \'');
    buffer.write(p.relative(file, from: target).replaceAll('\\', '/'));
    buffer.write('\' as ');
    buffer.write(prefix);
    buffer.write(index);
    buffer.write(';');

    imports.add(buffer.toString());
  }

  return imports.join(Platform.lineTerminator);
}
