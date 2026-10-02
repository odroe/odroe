import 'dart:io';

import 'package:path/path.dart' as p;

/// Atomically replaces [file] when [contents] changed.
bool writeStringIfChanged(File file, String contents) {
  if (file.existsSync() && file.readAsStringSync() == contents) return false;
  file.parent.createSync(recursive: true);
  final temporaryDirectory = file.parent.createTempSync('.odroe-write-');
  final temporary = File(p.join(temporaryDirectory.path, 'contents'));
  try {
    temporary.writeAsStringSync(contents, flush: true);
    temporary.renameSync(file.path);
    return true;
  } finally {
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  }
}
