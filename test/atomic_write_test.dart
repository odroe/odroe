import 'dart:io';

import 'package:odroe/src/atomic_write.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('atomic writes preserve conventional temporary siblings', () async {
    final directory = await Directory.systemTemp.createTemp(
      'odroe_atomic_write_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final target = File(p.join(directory.path, 'routes.dart'))
      ..writeAsStringSync('old');
    final sibling = File('${target.path}.tmp')
      ..writeAsStringSync('application-owned');

    expect(writeStringIfChanged(target, 'new'), isTrue);

    expect(target.readAsStringSync(), 'new');
    expect(sibling.readAsStringSync(), 'application-owned');
    expect(
      directory.listSync().where(
        (entity) => p.basename(entity.path).startsWith('.odroe-write-'),
      ),
      isEmpty,
    );
  });

  test(
    'atomic writes never follow a conventional temporary symlink',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'odroe_atomic_write_link_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final target = File(p.join(directory.path, 'routes.dart'))
        ..writeAsStringSync('old');
      final outside = File(p.join(directory.path, 'outside'))
        ..writeAsStringSync('outside');
      final sibling = Link('${target.path}.tmp')..createSync(outside.path);

      expect(writeStringIfChanged(target, 'new'), isTrue);

      expect(target.readAsStringSync(), 'new');
      expect(outside.readAsStringSync(), 'outside');
      expect(sibling.targetSync(), outside.path);
    },
    skip: Platform.isWindows
        ? 'Symbolic link permissions vary on Windows.'
        : false,
  );
}
