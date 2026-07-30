import 'dart:io';

/// Dart CLI used by nested commands under both `dart test` and `flutter test`.
String get dartExecutable {
  final name = Platform.resolvedExecutable
      .split(Platform.pathSeparator)
      .last
      .toLowerCase();
  if (name == 'dart' || name == 'dart.exe') {
    return Platform.resolvedExecutable;
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null || flutterRoot.isEmpty) return 'dart';
  final executable = Platform.isWindows ? 'dart.exe' : 'dart';
  return '$flutterRoot/bin/cache/dart-sdk/bin/$executable';
}

/// Serializes tests that invoke Dart commands against this checkout.
///
/// Dart's native-assets bundler writes shared files under `.dart_tool/lib`.
/// Concurrent commands can otherwise race while replacing the same dylib.
final class DartCommandLock {
  DartCommandLock._(this._file);

  final RandomAccessFile _file;
  var _released = false;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _file.unlock();
    } finally {
      await _file.close();
    }
  }
}

Future<DartCommandLock> acquireDartCommandLock() async {
  final lock = File('.dart_tool/odroe-test-dart-command.lock');
  await lock.parent.create(recursive: true);
  final file = await lock.open(mode: FileMode.append);
  try {
    await file.lock(FileLock.blockingExclusive);
    return DartCommandLock._(file);
  } on Object {
    await file.close();
    rethrow;
  }
}

Future<T> withDartCommandLock<T>(Future<T> Function() action) async {
  final lock = await acquireDartCommandLock();
  try {
    return await action();
  } finally {
    await lock.release();
  }
}
