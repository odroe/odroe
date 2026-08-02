import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'no_replace_rename.dart';

/// Runs one process used by [createProject].
typedef CreateCommandRunner =
    Future<int> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
      required StringSink out,
      required StringSink err,
      Map<String, String>? environment,
    });

const _supportedPlatforms = <String>{
  'android',
  'ios',
  'web',
  'linux',
  'macos',
  'windows',
};

/// Creates a new Flutter application and initializes the full-stack starter.
Future<void> createProject({
  required String directory,
  required String? odroePath,
  required String platforms,
  required String? organization,
  required String? projectName,
  required bool offline,
  required StringSink out,
  required StringSink err,
  CreateCommandRunner? runCommand,
}) async {
  final target = _targetDirectory(directory);
  final source = _odroeDirectory(odroePath);
  final selectedPlatforms = _platforms(platforms);
  final selectedOrganization = _optionalValue(organization, 'org');
  final selectedProjectName = _projectName(
    projectName ?? p.basename(target.path),
  )!;
  final flutter = _flutterCommand();

  final interruption = _CreateInterruption();
  late final Directory staging;
  try {
    interruption.start();
    staging = target.parent.createTempSync('.odroe-create-');
  } on Object catch (error, stackTrace) {
    try {
      await interruption.close();
    } on Object {
      // Preserve the setup failure before Odroe owns any project path.
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
  final providedRunner = runCommand;
  Future<int> runner(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required StringSink out,
    required StringSink err,
    Map<String, String>? environment,
  }) async {
    final beforeStart = interruption.exitCode;
    if (beforeStart != null) return beforeStart;
    final code = providedRunner == null
        ? await _runCommand(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            out: out,
            err: err,
            environment: environment,
            interruption: interruption,
          )
        : await providedRunner(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            out: out,
            err: err,
            environment: environment,
          );
    return interruption.exitCode ?? code;
  }

  var published = false;
  Object? failure;
  StackTrace? failureStack;
  try {
    await _requireSuccess(
      runner,
      flutter.executable,
      <String>[
        ...flutter.arguments,
        'create',
        '--empty',
        '--no-pub',
        '--no-overwrite',
        '--platforms=${selectedPlatforms.join(',')}',
        if (selectedOrganization != null) '--org=$selectedOrganization',
        '--project-name=$selectedProjectName',
        staging.path,
      ],
      workingDirectory: target.parent.path,
      stage: 'Flutter project creation',
      out: out,
      err: err,
      environment: flutter.environment,
    );
    await _requireSuccess(
      runner,
      flutter.executable,
      <String>[
        ...flutter.arguments,
        'pub',
        'add',
        if (offline) '--offline',
        'odroe@{"path":${jsonEncode(p.relative(source.path, from: staging.path))}}',
      ],
      workingDirectory: staging.path,
      stage: 'Odroe dependency resolution',
      out: out,
      err: err,
      environment: flutter.environment,
    );
    await _requireSuccess(
      runner,
      flutter.dartExecutable,
      const <String>['run', 'odroe', 'init', '--full-stack'],
      workingDirectory: staging.path,
      stage: 'Odroe starter initialization',
      out: out,
      err: err,
      environment: flutter.environment,
    );
    _requireNotInterrupted(interruption);
    _publish(staging, target);
    published = true;
    interruption.complete();
    out.writeln('Created the full-stack Odroe application at ${target.path}.');
  } on Object catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
  }

  if (!published) {
    try {
      _deleteOwnedStaging(staging);
      _reportSecondary(
        err,
        'Removed the incomplete staging path ${staging.path}.',
      );
    } on Object catch (cleanupError, cleanupStack) {
      _reportSecondary(
        err,
        'Could not remove the incomplete staging path ${staging.path} for '
        '${target.path}. $cleanupError',
      );
      failure ??= cleanupError;
      failureStack ??= cleanupStack;
    }
  }
  try {
    await interruption.close();
  } on Object catch (signalError, signalStack) {
    _reportSecondary(
      err,
      'Could not stop create signal handlers. $signalError',
    );
    failure ??= signalError;
    failureStack ??= signalStack;
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure, failureStack!);
  }
}

Future<void> _requireSuccess(
  CreateCommandRunner runCommand,
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required String stage,
  required StringSink out,
  required StringSink err,
  Map<String, String>? environment,
}) async {
  out.writeln('$stage...');
  final code = await runCommand(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    out: out,
    err: err,
    environment: environment,
  );
  if (code != 0) {
    throw ProcessException(executable, arguments, '$stage failed.', code);
  }
}

Future<int> _runCommand(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required StringSink out,
  required StringSink err,
  Map<String, String>? environment,
  required _CreateInterruption interruption,
}) async {
  final running = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  interruption.attach(running);
  try {
    final stdoutDone = running.stdout
        .transform(systemEncoding.decoder)
        .forEach(out.write);
    final stderrDone = running.stderr
        .transform(systemEncoding.decoder)
        .forEach(err.write);
    final code = await running.exitCode;
    interruption.detach(running);
    await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
    final interruptedCode = interruption.exitCode;
    if (interruptedCode != null) return interruptedCode;
    if (code >= 0) return code;
    final signal = -code;
    return signal < 128 ? 128 + signal : 1;
  } finally {
    interruption.detach(running);
  }
}

Directory _targetDirectory(String value) {
  if (value.trim().isEmpty) {
    throw const FormatException('create requires a target directory.');
  }
  final requested = Directory(p.normalize(p.absolute(value)));
  if (FileSystemEntity.typeSync(requested.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw FileSystemException(
      'odroe create will not overwrite an existing path.',
      requested.path,
    );
  }
  final parent = requested.parent;
  if (!parent.existsSync()) {
    throw FileSystemException(
      'The target parent directory does not exist.',
      parent.path,
    );
  }
  final resolvedParent = Directory(parent.resolveSymbolicLinksSync());
  final target = Directory(
    p.join(resolvedParent.path, p.basename(requested.path)),
  );
  if (FileSystemEntity.typeSync(target.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw FileSystemException(
      'odroe create will not overwrite an existing path.',
      target.path,
    );
  }
  return target;
}

Directory _odroeDirectory(String? value) {
  if (value == null || value.trim().isEmpty) {
    throw const FormatException(
      '--odroe-path is required while Odroe is used from source.',
    );
  }
  final directory = Directory(p.normalize(p.absolute(value)));
  if (!directory.existsSync()) {
    throw FileSystemException(
      'The Odroe source directory does not exist.',
      value,
    );
  }
  final resolved = Directory(directory.resolveSymbolicLinksSync());
  final pubspec = File(p.join(resolved.path, 'pubspec.yaml'));
  final library = File(p.join(resolved.path, 'lib', 'odroe.dart'));
  if (!pubspec.existsSync() || !library.existsSync()) {
    throw FileSystemException(
      '--odroe-path must point to an Odroe package checkout.',
      resolved.path,
    );
  }
  Object? document;
  try {
    document = loadYaml(pubspec.readAsStringSync());
  } on YamlException {
    throw FileSystemException('The Odroe pubspec is invalid.', pubspec.path);
  }
  if (document is! Map || document['name'] != 'odroe') {
    throw FileSystemException(
      '--odroe-path must point to the odroe package.',
      resolved.path,
    );
  }
  return resolved;
}

List<String> _platforms(String value) {
  final parts = value.split(',').map((part) => part.trim()).toList();
  if (parts.isEmpty || parts.any((part) => part.isEmpty)) {
    throw const FormatException('--platforms must not be empty.');
  }
  final result = <String>[];
  for (final platform in parts) {
    if (!_supportedPlatforms.contains(platform)) {
      throw FormatException('Unsupported Flutter platform: $platform');
    }
    if (!result.contains(platform)) result.add(platform);
  }
  return result;
}

String? _optionalValue(String? value, String option) {
  if (value == null) return null;
  final result = value.trim();
  if (result.isEmpty) throw FormatException('--$option must not be empty.');
  return result;
}

String? _projectName(String? value) {
  final result = _optionalValue(value, 'project-name');
  if (result != null && !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(result)) {
    throw FormatException('Invalid Flutter project name: $result');
  }
  return result;
}

void _requireNotInterrupted(_CreateInterruption interruption) {
  final code = interruption.exitCode;
  if (code == null) return;
  throw ProcessException(
    'odroe',
    const <String>['create'],
    'Project creation was interrupted.',
    code,
  );
}

void _publish(Directory staging, Directory target) {
  try {
    renameDirectoryWithoutReplace(staging, target);
  } on FileSystemException catch (error) {
    if (FileSystemEntity.typeSync(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException(
        'The create target appeared before the project could be published.',
        target.path,
      );
    }
    throw FileSystemException(
      'Could not publish the completed Odroe project.',
      target.path,
      error.osError,
    );
  }
}

void _deleteOwnedStaging(Directory staging) {
  switch (FileSystemEntity.typeSync(staging.path, followLinks: false)) {
    case FileSystemEntityType.directory:
      staging.deleteSync(recursive: true);
    case FileSystemEntityType.file:
      File(staging.path).deleteSync();
    case FileSystemEntityType.link:
      Link(staging.path).deleteSync();
    case FileSystemEntityType.notFound:
    case FileSystemEntityType.unixDomainSock:
    case FileSystemEntityType.pipe:
      break;
  }
}

void _reportSecondary(StringSink sink, String message) {
  try {
    sink.writeln(message);
  } on Object {
    // Preserve the operation failure when its diagnostic sink also fails.
  }
}

({
  String executable,
  List<String> arguments,
  Map<String, String>? environment,
  String dartExecutable,
})
_flutterCommand() {
  final roots = _flutterRoots();
  if (!Platform.isWindows) {
    for (final root in roots) {
      final flutter = File(p.join(root, 'bin', 'flutter'));
      final dart = File(
        p.join(root, 'bin', 'cache', 'dart-sdk', 'bin', 'dart'),
      );
      if (flutter.existsSync() && dart.existsSync()) {
        return (
          executable: flutter.resolveSymbolicLinksSync(),
          arguments: const <String>[],
          environment: <String, String>{
            'FLUTTER_ROOT': Directory(root).resolveSymbolicLinksSync(),
          },
          dartExecutable: dart.resolveSymbolicLinksSync(),
        );
      }
    }
    return (
      executable: 'flutter',
      arguments: const <String>[],
      environment: null,
      dartExecutable: _dartExecutable,
    );
  }

  for (final root in roots) {
    final dart = File(
      p.join(root, 'bin', 'cache', 'dart-sdk', 'bin', 'dart.exe'),
    );
    final packageConfig = File(
      p.join(
        root,
        'packages',
        'flutter_tools',
        '.dart_tool',
        'package_config.json',
      ),
    );
    final snapshot = File(
      p.join(root, 'bin', 'cache', 'flutter_tools.snapshot'),
    );
    if (dart.existsSync() &&
        packageConfig.existsSync() &&
        snapshot.existsSync()) {
      final mingit = Directory(p.join(root, 'bin', 'mingit', 'cmd'));
      final environment = Map<String, String>.of(Platform.environment);
      environment['FLUTTER_ROOT'] = Directory(root).resolveSymbolicLinksSync();
      if (mingit.existsSync()) {
        final pathKey = environment.containsKey('Path') ? 'Path' : 'PATH';
        final currentPath = environment[pathKey];
        final mingitPath = mingit.resolveSymbolicLinksSync();
        environment[pathKey] = currentPath == null || currentPath.isEmpty
            ? mingitPath
            : '$currentPath;$mingitPath';
      }
      final resolvedDart = dart.resolveSymbolicLinksSync();
      return (
        executable: resolvedDart,
        arguments: <String>[
          '--packages=${packageConfig.resolveSymbolicLinksSync()}',
          snapshot.resolveSymbolicLinksSync(),
        ],
        environment: environment,
        dartExecutable: resolvedDart,
      );
    }
  }
  throw const FileSystemException(
    'Could not locate a Flutter SDK without invoking flutter.bat.',
  );
}

List<String> _flutterRoots() {
  final roots = <String>{};
  final dartDirectory = File(Platform.resolvedExecutable).parent;
  final dartSdk = dartDirectory.parent;
  final cache = dartSdk.parent;
  final flutterBin = cache.parent;
  roots.add(flutterBin.parent.path);
  final configured = Platform.environment['FLUTTER_ROOT'];
  if (configured != null && configured.trim().isNotEmpty) {
    roots.add(p.normalize(p.absolute(_unquote(configured.trim()))));
  }
  final path = Platform.environment['PATH'] ?? Platform.environment['Path'];
  if (path != null) {
    final separator = Platform.isWindows ? ';' : ':';
    final executable = Platform.isWindows ? 'flutter.bat' : 'flutter';
    for (var entry in path.split(separator)) {
      entry = _unquote(entry.trim());
      if (entry.isEmpty) continue;
      final flutter = File(p.join(entry, executable));
      if (!flutter.existsSync()) {
        continue;
      }
      try {
        roots.add(File(flutter.resolveSymbolicLinksSync()).parent.parent.path);
      } on FileSystemException {
        roots.add(p.dirname(p.normalize(p.absolute(entry))));
      }
    }
  }
  return roots.toList(growable: false);
}

final class _CreateInterruption {
  static const _gracePeriod = Duration(seconds: 5);

  final _subscriptions = <StreamSubscription<ProcessSignal>>[];
  Process? _process;
  ProcessSignal? _signal;
  Timer? _forceKillTimer;
  var _completed = false;

  int? get exitCode => switch (_signal) {
    ProcessSignal.sigint => 130,
    ProcessSignal.sigterm => 143,
    _ => null,
  };

  void start() {
    _subscriptions.add(ProcessSignal.sigint.watch().listen(_interrupt));
    if (!Platform.isWindows) {
      _subscriptions.add(ProcessSignal.sigterm.watch().listen(_interrupt));
    }
  }

  void attach(Process process) {
    _process = process;
    final signal = _signal;
    if (signal != null) _terminate(process, signal, force: false);
  }

  void detach(Process process) {
    if (!identical(_process, process)) return;
    _process = null;
    _forceKillTimer?.cancel();
    _forceKillTimer = null;
  }

  void complete() {
    _completed = true;
    _forceKillTimer?.cancel();
    _forceKillTimer = null;
  }

  Future<void> close() async {
    _completed = true;
    _forceKillTimer?.cancel();
    _forceKillTimer = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  void _interrupt(ProcessSignal signal) {
    if (_completed) return;
    _signal ??= signal;
    final process = _process;
    if (process == null) return;
    _terminate(process, signal, force: _forceKillTimer != null);
  }

  void _terminate(
    Process process,
    ProcessSignal signal, {
    required bool force,
  }) {
    try {
      if (Platform.isWindows) {
        process.kill();
      } else {
        process.kill(force ? ProcessSignal.sigkill : signal);
      }
    } on Object {
      // The child may already have exited after receiving the terminal signal.
    }
    if (Platform.isWindows || force || _forceKillTimer != null) return;
    _forceKillTimer = Timer(_gracePeriod, () {
      if (!identical(_process, process)) return;
      try {
        process.kill(ProcessSignal.sigkill);
      } on Object {
        // The child may have exited during the grace period.
      }
    });
  }
}

String _unquote(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1)
    : value;

String get _dartExecutable {
  final resolved = Platform.resolvedExecutable;
  if (p.basenameWithoutExtension(resolved).toLowerCase() == 'dart') {
    return resolved;
  }
  return Platform.isWindows ? 'dart.exe' : 'dart';
}
