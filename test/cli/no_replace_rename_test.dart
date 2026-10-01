import 'dart:io';

import 'package:odroe/src/cli/no_replace_rename.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('renames a directory when the destination does not exist', () {
    final parent = Directory.systemTemp.createTempSync(
      'odroe_no_replace_rename_',
    );
    addTearDown(() => parent.deleteSync(recursive: true));
    final source = Directory(p.join(parent.path, 'source'))..createSync();
    File(p.join(source.path, 'sentinel')).writeAsStringSync('created');
    final destination = Directory(p.join(parent.path, 'destination'));

    renameDirectoryWithoutReplace(source, destination);

    expect(source.existsSync(), isFalse);
    expect(
      File(p.join(destination.path, 'sentinel')).readAsStringSync(),
      'created',
    );
  });

  test('does not replace an existing empty directory', () {
    final parent = Directory.systemTemp.createTempSync(
      'odroe_no_replace_empty_',
    );
    addTearDown(() => parent.deleteSync(recursive: true));
    final source = Directory(p.join(parent.path, 'source'))..createSync();
    final sourceFile = File(p.join(source.path, 'source'))
      ..writeAsStringSync('source');
    final destination = Directory(p.join(parent.path, 'destination'))
      ..createSync();

    expect(
      () => renameDirectoryWithoutReplace(source, destination),
      throwsA(isA<FileSystemException>()),
    );

    expect(sourceFile.readAsStringSync(), 'source');
    expect(destination.listSync(), isEmpty);
  });

  test('does not replace an existing file or non-empty directory', () {
    final parent = Directory.systemTemp.createTempSync(
      'odroe_no_replace_existing_',
    );
    addTearDown(() => parent.deleteSync(recursive: true));

    final fileSource = Directory(p.join(parent.path, 'file-source'))
      ..createSync();
    final destinationFile = File(p.join(parent.path, 'destination-file'))
      ..writeAsStringSync('owned file');
    expect(
      () => renameDirectoryWithoutReplace(
        fileSource,
        Directory(destinationFile.path),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(fileSource.existsSync(), isTrue);
    expect(destinationFile.readAsStringSync(), 'owned file');

    final directorySource = Directory(p.join(parent.path, 'directory-source'))
      ..createSync();
    final destinationDirectory = Directory(
      p.join(parent.path, 'destination-directory'),
    )..createSync();
    final sentinel = File(p.join(destinationDirectory.path, 'sentinel'))
      ..writeAsStringSync('owned directory');
    expect(
      () =>
          renameDirectoryWithoutReplace(directorySource, destinationDirectory),
      throwsA(isA<FileSystemException>()),
    );
    expect(directorySource.existsSync(), isTrue);
    expect(sentinel.readAsStringSync(), 'owned directory');
  });
}
