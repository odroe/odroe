import 'dart:io';

import 'package:odroe/press_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('odroe-press-');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('discovers index pages, nested pages, and frontmatter', () async {
    await _write(root, 'index.mdc', '''
---
title: Documentation
order: 1
language: en
---
# Documentation
''');
    await _write(root, 'guides/start.mdc', '''
---
title: Start
description: Build the first app.
order: 2
navigation:
  badge: New
---
# Start
''');
    await _write(root, 'draft.mdc', '''
---
title: Draft
draft: true
---
# Draft
''');

    final directory = PressDirectory(root.path, mount: '/docs/');
    final press = await directory.snapshot();

    expect(press.pages.map((page) => page.title), <String>[
      'Documentation',
      'Start',
    ]);
    expect(await directory.locations(), <Uri>[
      Uri(path: '/docs'),
      Uri(path: '/docs/guides/start'),
    ]);
    expect(
      (await directory.page(const <String>['guides', 'start']))?.description,
      'Build the first app.',
    );
    final navigation =
        press.page(const <String>[
              'guides',
              'start',
            ])!.frontmatter['navigation']!
            as Map<String, Object?>;
    expect(navigation, <String, Object?>{'badge': 'New'});
    expect(() => navigation['badge'] = 'Old', throwsUnsupportedError);

    final withDrafts = await PressDirectory(
      root.path,
      mount: '/docs/',
      includeDrafts: true,
    ).snapshot();
    expect(
      withDrafts.pages.map((page) => page.title),
      containsAll(<String>['Documentation', 'Start', 'Draft']),
    );
    expect(withDrafts.locations, contains(Uri(path: '/docs/draft')));
  });

  test(
    'reuses cache identity, single-flights scans, and removes files',
    () async {
      final file = await _write(root, 'page.mdc', '''
---
title: Before
---
# Before
''');
      final directory = PressDirectory(root.path);
      final futures = <Future<Press>>[
        for (var index = 0; index < 8; index++) directory.snapshot(),
      ];
      expect(
        futures.every((future) => identical(future, futures.first)),
        isTrue,
      );
      final snapshots = await Future.wait(futures);
      final before = snapshots.first;
      expect(
        snapshots.every((snapshot) => identical(snapshot, before)),
        isTrue,
      );
      expect(await directory.snapshot(), same(before));
      final beforePage = before.pages.single;

      await file.writeAsString('''
---
title: After a larger update
---
# After a larger update
''', flush: true);
      final after = await directory.snapshot();
      expect(after, isNot(same(before)));
      expect(after.pages.single, isNot(same(beforePage)));
      expect(after.pages.single.title, 'After a larger update');

      await file.delete();
      final deleted = await directory.snapshot();
      expect(deleted.pages, isEmpty);
      expect(deleted, isNot(same(after)));
      expect(await directory.snapshot(), same(deleted));
    },
  );

  test('keeps the last valid cache after failure and recovers', () async {
    await _write(root, 'stable.mdc', '''
---
title: Stable
---
# Stable
''');
    final changing = await _write(root, 'changing.mdc', '''
---
title: Before
---
# Before
''');
    final directory = PressDirectory(root.path);
    final before = await directory.snapshot();
    final stablePage = before.page(const <String>['stable']);

    await changing.writeAsString('''
---
order: first and invalid
---
# Broken
''', flush: true);
    await expectLater(
      directory.snapshot(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('changing.mdc'),
        ),
      ),
    );
    expect(before.page(const <String>['changing'])?.title, 'Before');

    await changing.writeAsString('''
---
title: Recovered
---
# Recovered
''', flush: true);
    final recovered = await directory.snapshot();
    expect(recovered.page(const <String>['changing'])?.title, 'Recovered');
    expect(recovered.page(const <String>['stable']), same(stablePage));
  });

  test('reports source paths for invalid known frontmatter', () async {
    final file = await _write(root, 'page.mdc', '''
---
title: Valid
---
# Valid
''');
    final directory = PressDirectory(root.path);
    await directory.snapshot();
    await file.writeAsString('''
---
order: first
---
# Broken
''', flush: true);
    await expectLater(
      directory.snapshot(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('page.mdc'),
        ),
      ),
    );
  });

  test('rejects case-insensitive location collisions', () async {
    await _write(root, 'Guide.mdc', '''
---
title: Guide
---
# Guide
''');
    await _write(root, 'guide/index.mdc', '''
---
title: Duplicate
---
# Duplicate
''');

    await expectLater(
      PressDirectory(root.path).snapshot(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('Guide.mdc'), contains('guide/index.mdc')),
        ),
      ),
    );
  });
}

Future<File> _write(Directory root, String path, String source) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(source, flush: true);
  return file;
}
