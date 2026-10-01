import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

const _atCurrentWorkingDirectory = -100;
const _linuxRenameNoReplace = 1;
const _macosRenameExclusive = 0x00000004;

/// Renames [source] to [destination] without replacing an existing path.
///
/// The operation is atomic when both paths are on the same file system.
void renameDirectoryWithoutReplace(Directory source, Directory destination) {
  late final int result;
  try {
    result = switch (Platform.operatingSystem) {
      'linux' => _renameLinux(source.path, destination.path),
      'macos' => _renameMacos(source.path, destination.path),
      'windows' => _renameWindows(source.path, destination.path),
      final operatingSystem => throw UnsupportedError(
        'Atomic no-replace rename is not supported on $operatingSystem.',
      ),
    };
  } on ArgumentError catch (error) {
    throw FileSystemException(
      'Atomic no-replace rename is unavailable: ${error.message}',
      destination.path,
    );
  } on UnsupportedError catch (error) {
    throw FileSystemException(
      error.message ?? 'Atomic no-replace rename is unavailable.',
      destination.path,
    );
  }
  if (result != 0) {
    throw FileSystemException(
      'Could not rename the directory without replacing an existing path.',
      destination.path,
    );
  }
}

int _renameLinux(String source, String destination) {
  final rename = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Int32, Pointer<Utf8>, Int32, Pointer<Utf8>, Uint32),
        int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int)
      >('renameat2');
  final sourcePointer = source.toNativeUtf8(allocator: calloc);
  final destinationPointer = destination.toNativeUtf8(allocator: calloc);
  try {
    return rename(
      _atCurrentWorkingDirectory,
      sourcePointer,
      _atCurrentWorkingDirectory,
      destinationPointer,
      _linuxRenameNoReplace,
    );
  } finally {
    calloc
      ..free(sourcePointer)
      ..free(destinationPointer);
  }
}

int _renameMacos(String source, String destination) {
  final rename = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Uint32),
        int Function(Pointer<Utf8>, Pointer<Utf8>, int)
      >('renamex_np');
  final sourcePointer = source.toNativeUtf8(allocator: calloc);
  final destinationPointer = destination.toNativeUtf8(allocator: calloc);
  try {
    return rename(sourcePointer, destinationPointer, _macosRenameExclusive);
  } finally {
    calloc
      ..free(sourcePointer)
      ..free(destinationPointer);
  }
}

int _renameWindows(String source, String destination) {
  final rename = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int)
      >('MoveFileExW');
  final sourcePointer = source.toNativeUtf16(allocator: calloc);
  final destinationPointer = destination.toNativeUtf16(allocator: calloc);
  try {
    return rename(sourcePointer, destinationPointer, 0) == 0 ? -1 : 0;
  } finally {
    calloc
      ..free(sourcePointer)
      ..free(destinationPointer);
  }
}
