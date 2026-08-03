import 'dart:io';

import 'package:odroe/src/cli/build.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('Native Web staging layers Flutter and prerender outputs', () {
    final state = Directory.systemTemp.createTempSync('odroe-native-web-');
    addTearDown(() => state.deleteSync(recursive: true));
    final bundle = Directory(p.join(state.path, 'bundle'))..createSync();
    final flutter = Directory(p.join(state.path, 'flutter'))..createSync();
    final prerender = Directory(p.join(state.path, 'prerender'))..createSync();
    File(p.join(flutter.path, 'main.dart.js')).writeAsStringSync('client');
    File(p.join(flutter.path, 'shared.txt')).writeAsStringSync('flutter');
    File(p.join(prerender.path, 'shared.txt')).writeAsStringSync('prerender');
    File(p.join(prerender.path, 'posts', '42', 'index.html'))
      ..createSync(recursive: true)
      ..writeAsStringSync('post');

    installNativeWeb(
      bundle,
      flutterOutput: flutter,
      prerenderOutput: prerender,
    );

    final web = p.join(bundle.path, 'build', 'web');
    expect(File(p.join(web, 'main.dart.js')).readAsStringSync(), 'client');
    expect(File(p.join(web, 'shared.txt')).readAsStringSync(), 'prerender');
    expect(
      File(p.join(web, 'posts', '42', 'index.html')).readAsStringSync(),
      'post',
    );
    expect(
      File(p.join(flutter.path, 'shared.txt')).readAsStringSync(),
      'flutter',
    );
  });

  test('Native Web staging accepts one shared output root', () {
    final state = Directory.systemTemp.createTempSync(
      'odroe-native-web-shared-',
    );
    addTearDown(() => state.deleteSync(recursive: true));
    final bundle = Directory(p.join(state.path, 'bundle'))..createSync();
    final output = Directory(p.join(state.path, 'web'))..createSync();
    File(p.join(output.path, 'index.html')).writeAsStringSync('shared');

    installNativeWeb(bundle, flutterOutput: output, prerenderOutput: output);

    expect(
      File(
        p.join(bundle.path, 'build', 'web', 'index.html'),
      ).readAsStringSync(),
      'shared',
    );
  });

  test('build directory identity follows the actual volume case semantics', () {
    final state = Directory.systemTemp.createTempSync(
      'odroe-native-web-identity-',
    );
    addTearDown(() => state.deleteSync(recursive: true));
    final probe = Directory(p.join(state.path, 'CaseProbe'))..createSync();
    final alternateProbe = Directory(p.join(state.path, 'caseProbe'));
    final ignoresCase =
        alternateProbe.existsSync() &&
        FileSystemEntity.identicalSync(probe.path, alternateProbe.path);
    probe.deleteSync();
    final upper = Directory(p.join(state.path, 'Web'));
    final lower = Directory(p.join(state.path, 'web'));

    expect(upper.existsSync(), isFalse);
    expect(lower.existsSync(), isFalse);
    expect(sameBuildDirectory(upper, lower), ignoresCase);
  });

  test('build directory publication rolls every target back', () {
    final state = Directory.systemTemp.createTempSync(
      'odroe-native-web-publication-',
    );
    addTearDown(() => state.deleteSync(recursive: true));
    final firstStage = Directory(p.join(state.path, 'first-stage'))
      ..createSync();
    final secondStage = Directory(p.join(state.path, 'second-stage'))
      ..createSync();
    final firstTarget = Directory(p.join(state.path, 'first'))..createSync();
    final secondTarget = Directory(p.join(state.path, 'second'))..createSync();
    File(p.join(firstStage.path, 'version')).writeAsStringSync('new first');
    File(p.join(secondStage.path, 'version')).writeAsStringSync('new second');
    File(p.join(firstTarget.path, 'version')).writeAsStringSync('old first');
    File(p.join(secondTarget.path, 'version')).writeAsStringSync('old second');

    expect(
      () => replaceBuildDirectories<void>(
        outputs: <BuildDirectoryPublication>[
          (source: firstStage, target: firstTarget),
          (source: secondStage, target: secondTarget),
        ],
        commit: () => throw StateError('final validation failed'),
        out: StringBuffer(),
      ),
      throwsStateError,
    );

    expect(
      File(p.join(firstTarget.path, 'version')).readAsStringSync(),
      'old first',
    );
    expect(
      File(p.join(secondTarget.path, 'version')).readAsStringSync(),
      'old second',
    );
    expect(firstStage.existsSync(), isFalse);
    expect(secondStage.existsSync(), isFalse);
    expect(
      state
          .listSync()
          .map((entity) => p.basename(entity.path))
          .where((name) => name.contains('.odroe-')),
      isEmpty,
    );
  });

  test('Native Web staging preserves case-distinct layers when supported', () {
    final state = Directory.systemTemp.createTempSync('odroe-native-web-case-');
    addTearDown(() => state.deleteSync(recursive: true));
    final bundle = Directory(p.join(state.path, 'bundle'))..createSync();
    final flutter = Directory(p.join(state.path, 'Web'))..createSync();
    final prerender = Directory(p.join(state.path, 'web'))..createSync();
    File(p.join(flutter.path, 'main.dart.js')).writeAsStringSync('client');
    File(p.join(prerender.path, 'posts.html')).writeAsStringSync('prerender');

    installNativeWeb(
      bundle,
      flutterOutput: flutter,
      prerenderOutput: prerender,
    );

    final web = p.join(bundle.path, 'build', 'web');
    expect(File(p.join(web, 'main.dart.js')).readAsStringSync(), 'client');
    expect(File(p.join(web, 'posts.html')).readAsStringSync(), 'prerender');
  });

  test('Native Web staging rejects overlapping source and destination', () {
    final state = Directory.systemTemp.createTempSync(
      'odroe-native-web-overlap-',
    );
    addTearDown(() => state.deleteSync(recursive: true));
    final bundle = Directory(p.join(state.path, 'bundle'))..createSync();
    final source = Directory(p.join(bundle.path, 'build'))..createSync();
    File(p.join(source.path, 'client.js')).writeAsStringSync('client');

    expect(
      () => installNativeWeb(
        bundle,
        flutterOutput: source,
        prerenderOutput: null,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(p.join(source.path, 'client.js')).readAsStringSync(), 'client');
  });

  test('Native Web staging rejects conflicting layer entity types', () {
    final state = Directory.systemTemp.createTempSync(
      'odroe-native-web-conflict-',
    );
    addTearDown(() => state.deleteSync(recursive: true));
    final bundle = Directory(p.join(state.path, 'bundle'))..createSync();
    final flutter = Directory(p.join(state.path, 'flutter'))..createSync();
    final prerender = Directory(p.join(state.path, 'prerender'))..createSync();
    File(p.join(flutter.path, 'assets')).writeAsStringSync('file');
    File(p.join(prerender.path, 'assets', 'index.html'))
      ..createSync(recursive: true)
      ..writeAsStringSync('directory');

    expect(
      () => installNativeWeb(
        bundle,
        flutterOutput: flutter,
        prerenderOutput: prerender,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(p.join(flutter.path, 'assets')).readAsStringSync(), 'file');
    expect(
      File(p.join(prerender.path, 'assets', 'index.html')).readAsStringSync(),
      'directory',
    );
  });

  test(
    'Native Web staging rejects file and directory links',
    () {
      final state = Directory.systemTemp.createTempSync(
        'odroe-native-web-links-',
      );
      addTearDown(() => state.deleteSync(recursive: true));
      final outsideFile = File(p.join(state.path, 'outside.js'))
        ..writeAsStringSync('outside file');
      final outsideDirectory = Directory(p.join(state.path, 'outside'))
        ..createSync();
      File(
        p.join(outsideDirectory.path, 'index.html'),
      ).writeAsStringSync('outside directory');

      for (final linkTarget in <String>[
        outsideFile.path,
        outsideDirectory.path,
      ]) {
        final id = p.basename(linkTarget);
        final bundle = Directory(p.join(state.path, 'bundle-$id'))
          ..createSync();
        final source = Directory(p.join(state.path, 'source-$id'))
          ..createSync();
        Link(p.join(source.path, 'linked')).createSync(linkTarget);

        expect(
          () => installNativeWeb(
            bundle,
            flutterOutput: source,
            prerenderOutput: null,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          Directory(p.join(bundle.path, 'build', 'web')).existsSync(),
          isFalse,
        );
      }
      final rootBundle = Directory(p.join(state.path, 'bundle-root-link'))
        ..createSync();
      final rootLink = Link(p.join(state.path, 'source-root-link'))
        ..createSync(outsideDirectory.path);
      expect(
        () => installNativeWeb(
          rootBundle,
          flutterOutput: Directory(rootLink.path),
          prerenderOutput: null,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        Directory(p.join(rootBundle.path, 'build', 'web')).existsSync(),
        isFalse,
      );
      expect(outsideFile.readAsStringSync(), 'outside file');
      expect(
        File(p.join(outsideDirectory.path, 'index.html')).readAsStringSync(),
        'outside directory',
      );
    },
    skip: Platform.isWindows
        ? 'Symbolic link permissions vary on Windows.'
        : false,
  );
}
