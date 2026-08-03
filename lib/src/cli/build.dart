import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/server_io.dart';
import 'package:path/path.dart' as p;

import '../atomic_write.dart';
import '../database_sqlite/migration.dart';
import 'prerender_manifest.dart';
import 'project.dart';

/// Server artifact selected by `odroe build`.
enum ServerBuildTarget {
  /// A deployable Dart VM CLI bundle.
  native,

  /// A JavaScript module for Cloudflare Workers.
  cloudflare,
}

/// Builds the selected Flutter target and optional Odroe server artifact.
Future<int> runBuild(
  CliProject project, {
  required bool serverOnly,
  required bool buildServer,
  required ServerBuildTarget serverTarget,
  required String? serverArtifact,
  required String? sqliteMigrations,
  required bool prerender,
  required String prerenderOutput,
  required int prerenderConcurrency,
  required bool prerenderCrawl,
  required int prerenderMaxRoutes,
  required int prerenderMaxResponseBytes,
  required List<String> flutterArguments,
  required StringSink out,
  required StringSink err,
}) async {
  if (serverOnly && !buildServer) {
    err.writeln('--server-only cannot be combined with --no-server.');
    return 64;
  }
  final inspectedRoutes = project.compiler.compile();
  if (inspectedRoutes.hasErrors) {
    generateRoutes(project, out, err, compiled: inspectedRoutes);
    return 1;
  }
  if (!serverOnly && inspectedRoutes.hasFlutter && flutterArguments.isEmpty) {
    err.writeln(
      'Choose a Flutter build target, for example: '
      'dart run odroe build apk or dart run odroe build web.',
    );
    return 64;
  }
  final flutterTarget = flutterArguments
      .where((argument) => !argument.startsWith('-'))
      .firstOrNull;
  final shouldPrerender =
      prerender &&
      !serverOnly &&
      (!inspectedRoutes.hasFlutter || flutterTarget == 'web');
  final buildsNativeServer =
      buildServer && serverTarget == ServerBuildTarget.native;
  if (sqliteMigrations != null && !buildsNativeServer && !shouldPrerender) {
    err.writeln(
      '--sqlite-migrations requires a Native server build or prerender.',
    );
    return 64;
  }
  final selectedSqliteMigrations = buildsNativeServer || shouldPrerender
      ? sqliteMigrations ?? project.configuredSqliteMigrations
      : null;
  final migrationOption = sqliteMigrations == null
      ? 'odroe.yaml sqlite_migrations'
      : '--sqlite-migrations';
  final migrationSource = _resolveSqliteMigrations(
    project,
    selectedSqliteMigrations,
    option: migrationOption,
  );
  final generatedRouteOutputs = <String>[
    project.compiler.outputFile.path,
    project.compiler.serverOutputFile.path,
  ];
  if (migrationSource != null &&
      generatedRouteOutputs.any(
        (path) => _pathsOverlap(migrationSource.path, path),
      )) {
    err.writeln(
      'SQLite migration source and generated route outputs must not overlap.',
    );
    return 64;
  }
  String? artifactPath;
  if (buildServer) {
    artifactPath = resolveBuildOutputPath(
      project.root,
      serverArtifact ?? _defaultServerArtifact(serverTarget),
      option: '--server-artifact',
    );
  }
  final serverOutputPath = artifactPath;
  final serverOutputs = serverOutputPath == null
      ? const <String>[]
      : <String>[
          serverOutputPath,
          if (serverTarget == ServerBuildTarget.cloudflare) ...<String>[
            p.join(p.dirname(serverOutputPath), 'worker.mjs'),
            '$serverOutputPath.deps',
          ],
        ];
  if (migrationSource != null &&
      serverOutputs.any((path) => _pathsOverlap(migrationSource.path, path))) {
    err.writeln(
      'SQLite migration source and server artifact outputs must not overlap.',
    );
    return 64;
  }
  if (serverOutputs.any(
    (path) => generatedRouteOutputs.any(
      (generatedPath) => _pathsOverlap(path, generatedPath),
    ),
  )) {
    err.writeln(
      'Generated route outputs and server artifact outputs must not overlap.',
    );
    return 64;
  }
  if (serverOutputs.any(
    (path) => _pathsOverlap(path, project.compiler.routesDirectory.path),
  )) {
    err.writeln('Route source and server artifact outputs must not overlap.');
    return 64;
  }
  final flutterOutputs = serverOnly
      ? const <Directory>[]
      : _flutterBuildOutputs(project, flutterTarget, flutterArguments);
  for (final flutterOutput in flutterOutputs) {
    if (migrationSource != null &&
        _pathsOverlap(flutterOutput.path, migrationSource.path)) {
      err.writeln(
        'Flutter build output and SQLite migration source must not overlap.',
      );
      return 64;
    }
    if (_pathsOverlap(
      flutterOutput.path,
      project.compiler.routesDirectory.path,
    )) {
      err.writeln('Flutter build output and route source must not overlap.');
      return 64;
    }
    if (generatedRouteOutputs.any(
      (path) => _pathsOverlap(flutterOutput.path, path),
    )) {
      err.writeln(
        'Flutter build output and generated route outputs must not overlap.',
      );
      return 64;
    }
    if (serverOutputs.any((path) => _pathsOverlap(flutterOutput.path, path))) {
      err.writeln(
        'Flutter build output and server artifact outputs must not overlap.',
      );
      return 64;
    }
  }
  var routes = const <String>[];
  late final Directory outputDirectory;
  if (shouldPrerender) {
    outputDirectory = Directory(
      resolveBuildOutputPath(
        project.root,
        prerenderOutput,
        option: '--prerender-output',
      ),
    );
    if (migrationSource != null &&
        _pathsOverlap(migrationSource.path, outputDirectory.path)) {
      err.writeln(
        'SQLite migration source and --prerender-output must not overlap.',
      );
      return 64;
    }
    if (generatedRouteOutputs.any(
      (path) => _pathsOverlap(path, outputDirectory.path),
    )) {
      err.writeln(
        'Generated route outputs and --prerender-output must not overlap.',
      );
      return 64;
    }
    if (_pathsOverlap(
      project.compiler.routesDirectory.path,
      outputDirectory.path,
    )) {
      err.writeln('Route source and --prerender-output must not overlap.');
      return 64;
    }
    if (serverOutputPath != null) {
      if (serverOutputs.any(
        (path) => _pathsOverlap(path, outputDirectory.path),
      )) {
        err.writeln(
          '--server-artifact and --prerender-output must not overlap.',
        );
        return 64;
      }
    }
  }
  final generated = generateRoutes(
    project,
    out,
    err,
    compiled: inspectedRoutes,
  );
  if (generated == null) return 1;
  if (shouldPrerender) {
    try {
      routes = await loadPrerenderLocations(
        projectRoot: project.root,
        packageName: project.packageName,
        staticLocations: generated.staticRoutes,
        maxRoutes: prerenderMaxRoutes,
      );
    } on StateError catch (error) {
      err.writeln(error.message);
      return 1;
    }
  }
  if (buildServer) {
    final code = await _buildServer(
      project,
      target: serverTarget,
      outputPath: artifactPath!,
      migrationSource: migrationSource,
      out: out,
    );
    if (code != 0) return code;
  }
  if (!serverOnly && flutterArguments.isNotEmpty) {
    final flutter = await startProjectProcess('flutter', <String>[
      'build',
      ...flutterArguments,
    ], project: project);
    final code = await flutter.exitCode;
    if (code != 0) return code;
  }
  if (!shouldPrerender) return 0;
  final stagingDirectory = generated.hasFlutter
      ? null
      : _siblingTemporaryDirectory(outputDirectory, 'staging');
  final renderDirectory = stagingDirectory ?? outputDirectory;
  try {
    renderDirectory.createSync(recursive: true);
    final assets = await _copyPublicAssets(project, renderDirectory);
    if (assets > 0) out.writeln('Copied $assets public assets.');
    final prerenderFromSource =
        !buildServer || serverTarget == ServerBuildTarget.cloudflare;
    final prerenderExecutable = prerenderFromSource
        ? Platform.resolvedExecutable
        : p.join(artifactPath!, 'bin', _nativeServerExecutableName);
    final prerenderArguments = prerenderFromSource
        ? <String>['run', project.bootstrap.path]
        : const <String>[];
    final prerenderMigrationSource =
        migrationSource != null && !prerenderFromSource
        ? Directory(p.join(artifactPath!, 'migrations'))
        : migrationSource;
    final code = await _prerenderBuild(
      project,
      executable: prerenderExecutable,
      arguments: prerenderArguments,
      routes: routes,
      outputDirectory: renderDirectory,
      reportedOutputDirectory: outputDirectory,
      concurrency: prerenderConcurrency,
      crawlLinks: prerenderCrawl,
      maxRoutes: prerenderMaxRoutes,
      maxResponseBytes: prerenderMaxResponseBytes,
      startupTimeout: prerenderFromSource
          ? const Duration(minutes: 1)
          : const Duration(seconds: 20),
      migrationSource: prerenderMigrationSource,
      out: out,
      err: err,
    );
    if (code != 0) return code;
    if (stagingDirectory != null) {
      _replaceDirectory(stagingDirectory, outputDirectory);
    }
    return 0;
  } finally {
    if (stagingDirectory?.existsSync() ?? false) {
      stagingDirectory!.deleteSync(recursive: true);
    }
  }
}

String _defaultServerArtifact(ServerBuildTarget target) => switch (target) {
  ServerBuildTarget.native => 'build/odroe/server',
  ServerBuildTarget.cloudflare => 'build/odroe/cloudflare/server.js',
};

List<Directory> _flutterBuildOutputs(
  CliProject project,
  String? target,
  List<String> arguments,
) {
  if (target == null) return const <Directory>[];
  final explicitOutput = switch (target) {
    'aar' || 'ios-framework' || 'macos-framework' || 'swift-package' || 'web' =>
      _optionValue(arguments, const <String>['--output', '--output-dir', '-o']),
    'bundle' => _optionValue(arguments, const <String>['--asset-dir']),
    _ => null,
  };
  final outputs = <String>{};
  void add(String path) => outputs.add(p.normalize(path));
  if (explicitOutput != null && explicitOutput.isNotEmpty) {
    add(
      p.isAbsolute(explicitOutput)
          ? p.normalize(explicitOutput)
          : p.normalize(p.join(project.root.path, explicitOutput)),
    );
  }

  final defaultRoot = p.join(project.root.path, 'build');
  final configuredRoot = _flutterBuildRoot(project.root).path;
  final suffix = switch (target) {
    'aar' => 'host',
    'apk' || 'appbundle' => 'app',
    'bundle' => 'flutter_assets',
    'ios' || 'ios-framework' || 'ipa' => 'ios',
    'linux' => 'linux',
    'macos' || 'macos-framework' => 'macos',
    'swift-package' =>
      _optionValue(arguments, const <String>['--platform']) == 'macos'
          ? 'macos'
          : 'ios',
    'web' => 'web',
    'windows' => 'windows',
    _ => null,
  };
  if (suffix != null && explicitOutput == null) {
    add(p.join(configuredRoot, suffix));
  }
  if (target case 'aar' || 'ios-framework' || 'macos-framework') {
    add(p.join(defaultRoot, suffix!));
    add(p.join(configuredRoot, suffix));
  }
  if (target == 'swift-package') {
    if (explicitOutput == null) {
      add(p.join(defaultRoot, suffix!, 'SwiftPackages'));
    }
    add(p.join(configuredRoot, suffix!));
  }
  return <Directory>[
    for (final output in outputs)
      Directory(_realPathForOverlap(output)).absolute,
  ];
}

Directory _flutterBuildRoot(Directory project) {
  final environment = Platform.environment;
  final home = environment[Platform.isWindows ? 'APPDATA' : 'HOME'] ?? '.';
  final legacy = File(p.join(home, '.flutter_settings'));
  final settings = Platform.isLinux || Platform.isMacOS
      ? (legacy.existsSync()
            ? legacy
            : File(
                p.join(
                  environment['XDG_CONFIG_HOME'] ??
                      p.join(home, '.config', 'flutter'),
                  'settings',
                ),
              ))
      : legacy;
  var buildDirectory = 'build';
  if (settings.existsSync()) {
    try {
      final decoded = jsonDecode(settings.readAsStringSync());
      final configured = decoded is Map<String, Object?>
          ? decoded['build-dir']
          : null;
      if (configured is String) {
        buildDirectory = configured;
      }
    } on FormatException {
      // Flutter ignores malformed settings and falls back to build/.
    } on FileSystemException {
      // Flutter reports unreadable settings later; retain the safe default.
    }
  }
  if (p.isAbsolute(buildDirectory)) {
    throw const FormatException(
      'Flutter build-dir configuration must be relative.',
    );
  }
  return Directory(p.normalize(p.join(project.path, buildDirectory))).absolute;
}

String? _optionValue(List<String> arguments, List<String> options) {
  String? value;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    for (final option in options) {
      if (argument == option) {
        value = index + 1 < arguments.length ? arguments[index + 1] : null;
      }
      if (argument.startsWith('$option=')) {
        value = argument.substring(option.length + 1);
      }
    }
  }
  return value;
}

String _realPathForOverlap(String path) {
  var existing = p.normalize(Directory(path).absolute.path);
  final suffix = <String>[];
  while (FileSystemEntity.typeSync(existing, followLinks: false) ==
      FileSystemEntityType.notFound) {
    final parent = p.dirname(existing);
    if (p.equals(parent, existing)) break;
    suffix.insert(0, p.basename(existing));
    existing = parent;
  }
  final resolved = Directory(existing).resolveSymbolicLinksSync();
  return p.normalize(p.joinAll(<String>[resolved, ...suffix]));
}

bool _pathsOverlap(String left, String right) {
  final normalizedLeft = p.normalize(left).toLowerCase();
  final normalizedRight = p.normalize(right).toLowerCase();
  return p.equals(normalizedLeft, normalizedRight) ||
      p.isWithin(normalizedLeft, normalizedRight) ||
      p.isWithin(normalizedRight, normalizedLeft);
}

Directory _siblingTemporaryDirectory(Directory target, String suffix) {
  final id = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
  return Directory(
    p.join(target.parent.path, '.${p.basename(target.path)}.odroe-$suffix-$id'),
  );
}

void _replaceDirectory(Directory source, Directory target) {
  final backup = _siblingTemporaryDirectory(target, 'backup');
  var movedTarget = false;
  try {
    if (target.existsSync()) {
      target.renameSync(backup.path);
      movedTarget = true;
    }
    source.renameSync(target.path);
  } on Object {
    if (movedTarget && !target.existsSync() && backup.existsSync()) {
      try {
        backup.renameSync(target.path);
      } on FileSystemException catch (error) {
        throw FileSystemException(
          'Could not restore the previous prerender output; it remains at '
          '${backup.path}. ${error.message}',
          target.path,
          error.osError,
        );
      }
    }
    rethrow;
  }
  if (backup.existsSync()) backup.deleteSync(recursive: true);
}

/// Resolves one user-selected artifact path inside a project's real build tree.
///
/// Absolute paths, parent traversal, the build directory itself, and existing
/// symbolic-link components are rejected before any write or recursive delete.
String resolveBuildOutputPath(
  Directory projectRoot,
  String relativePath, {
  required String option,
}) {
  if (relativePath.isEmpty || p.isAbsolute(relativePath)) {
    throw FormatException('$option must be a relative path inside build/.');
  }
  if (p.split(relativePath).contains('..')) {
    throw FormatException('$option cannot contain parent traversal.');
  }

  final root = p.normalize(projectRoot.absolute.path);
  final buildRoot = p.normalize(p.join(root, 'build'));
  final resolved = p.normalize(p.join(root, relativePath));
  if (!p.isWithin(buildRoot, resolved)) {
    throw FormatException('$option must resolve inside build/.');
  }

  var current = root;
  for (final component in p.split(p.relative(resolved, from: root))) {
    current = p.join(current, component);
    if (FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FormatException('$option cannot traverse a symbolic link.');
    }
  }
  return resolved;
}

Future<int> _buildServer(
  CliProject project, {
  required ServerBuildTarget target,
  required String outputPath,
  required Directory? migrationSource,
  required StringSink out,
}) async {
  Directory(p.dirname(outputPath)).createSync(recursive: true);
  if (target == ServerBuildTarget.native) {
    return _compileNativeServer(
      project,
      Directory(outputPath),
      migrationSource: migrationSource,
      out: out,
    );
  }
  return buildCloudflareServer(project, artifact: File(outputPath), out: out);
}

/// Compiles and atomically replaces one Cloudflare Worker artifact.
///
/// Compilation happens beside the final artifact. A failed compile leaves the
/// previous runnable Worker untouched, which lets local development keep its
/// last-known-good server while the source is being fixed.
Future<int> buildCloudflareServer(
  CliProject project, {
  required File artifact,
  required StringSink out,
  Future<void>? cancelled,
}) async {
  if (p.extension(artifact.path) != '.js') {
    throw const FormatException(
      'Cloudflare server artifacts must use the .js extension.',
    );
  }
  artifact.parent.createSync(recursive: true);
  project.writeFetchBootstrap();
  final staging = artifact.parent.createTempSync('.odroe-cloudflare-');
  final stagedArtifact = File(p.join(staging.path, p.basename(artifact.path)));
  try {
    final process =
        await startProjectProcess(Platform.resolvedExecutable, <String>[
          'compile',
          'js',
          '-O4',
          '--no-source-maps',
          project.fetchBootstrap.path,
          '-o',
          stagedArtifact.path,
        ], project: project);
    final code = await _compilerExitCode(process, cancelled);
    if (code != 0) return code;

    final stagedDependencies = File('${stagedArtifact.path}.deps');
    if (stagedDependencies.existsSync()) {
      stagedDependencies.renameSync('${artifact.path}.deps');
    }
    stagedArtifact.renameSync(artifact.path);
    final worker = File(p.join(artifact.parent.path, 'worker.mjs'));
    writeStringIfChanged(
      worker,
      _cloudflareWorkerSource(p.basename(artifact.path)),
    );
    out.writeln(
      'Built Cloudflare Worker -> '
      '${p.relative(worker.path, from: project.root.path)}',
    );
    return 0;
  } finally {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
  }
}

Future<int> _compilerExitCode(Process process, Future<void>? cancelled) async {
  final exitCode = process.exitCode;
  if (cancelled == null) return exitCode;
  var cancellationWon = false;
  final code = await Future.any<int>(<Future<int>>[
    exitCode,
    cancelled.then((_) {
      cancellationWon = true;
      return 130;
    }),
  ]);
  if (!cancellationWon) return code;
  await _terminateProcess(process, exitCode);
  return 130;
}

Future<void> _terminateProcess(Process process, Future<int> exitCode) async {
  process.kill(ProcessSignal.sigterm);
  try {
    await exitCode.timeout(const Duration(seconds: 5));
    return;
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
  }
  try {
    await exitCode.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    // Do not let an unresponsive child keep the CLI alive forever.
  }
}

Future<int> _compileNativeServer(
  CliProject project,
  Directory bundle, {
  required Directory? migrationSource,
  required StringSink out,
}) async {
  bundle.parent.createSync(recursive: true);
  _validateNativeBundleOutput(
    bundle,
    selectedMigrations: migrationSource != null,
  );
  final migrations = migrationSource == null
      ? null
      : readSqliteMigrations(migrationSource.path);
  final staging = bundle.parent.createTempSync('.odroe-native-');
  final buildOutput = Directory(p.join(staging.path, 'build'));
  final stagedMigrations = migrationSource == null
      ? null
      : (Directory(p.join(staging.path, 'migrations'))..createSync());
  try {
    for (final migration in migrations ?? const <SqliteMigration>[]) {
      final stagedMigration = File(
        p.join(stagedMigrations!.path, migration.name),
      );
      File(
        p.join(migrationSource!.path, migration.name),
      ).copySync(stagedMigration.path);
      if (stagedMigration.readAsStringSync() != migration.sql) {
        throw FileSystemException(
          'SQLite migration changed while the native bundle was staged.',
          p.join(migrationSource.path, migration.name),
        );
      }
    }
    final process = await startProjectProcess(
      Platform.resolvedExecutable,
      <String>[
        'build',
        'cli',
        '--target',
        project.bootstrap.path,
        '--output',
        buildOutput.path,
      ],
      project: project,
    );
    final code = await process.exitCode;
    if (code != 0) return code;
    final stagedBundle = Directory(p.join(buildOutput.path, 'bundle'));
    final stagedExecutable = File(
      p.join(stagedBundle.path, 'bin', _nativeServerExecutableName),
    );
    if (FileSystemEntity.typeSync(stagedExecutable.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException(
        'Dart did not emit the expected Native server executable.',
        stagedExecutable.path,
      );
    }
    Directory(p.join(stagedBundle.path, 'lib')).createSync();
    File(
      p.join(stagedBundle.path, _nativeBundleOwnerFile),
    ).writeAsStringSync(_nativeBundleOwner, flush: true);
    if (stagedMigrations != null) {
      stagedMigrations.renameSync(p.join(stagedBundle.path, 'migrations'));
    }
    if (migrationSource != null) {
      verifySqliteMigrationSnapshot(migrationSource, migrations!);
    }
    _validateNativeBundleOutput(
      bundle,
      selectedMigrations: migrationSource != null,
    );
    final publicationWarning = await replaceNativeBundle(
      stagedBundle: stagedBundle,
      bundle: bundle,
      lockFile: File(
        p.join(project.root.path, '.dart_tool', 'odroe', 'native-build.lock'),
      ),
    );
    if (publicationWarning != null) out.writeln(publicationWarning);
    out.writeln(
      'Built Native server bundle -> '
      '${p.relative(bundle.path, from: project.root.path)}',
    );
    if (migrations != null) {
      out.writeln(
        'Bundled ${migrations.length} SQLite migrations -> '
        '${p.relative(p.join(bundle.path, 'migrations'), from: project.root.path)}',
      );
    }
    return 0;
  } finally {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
  }
}

const _nativeBundleOwnerFile = '.odroe-native-bundle';
const _nativeBundleOwner = 'odroe-native-bundle-v1\n';
String get _nativeServerExecutableName =>
    Platform.isWindows ? 'server.exe' : 'server';

FileSystemEntityType _validateNativeBundleOutput(
  Directory bundle, {
  required bool selectedMigrations,
}) {
  final outputType = FileSystemEntity.typeSync(bundle.path, followLinks: false);
  if (outputType == FileSystemEntityType.notFound) return outputType;
  if (outputType != FileSystemEntityType.directory ||
      !_isOwnedNativeBundle(bundle)) {
    throw FileSystemException(
      'Native server output must be an Odroe-owned bundle directory. Move or '
      'remove the existing output explicitly.',
      bundle.path,
    );
  }
  if (!selectedMigrations &&
      FileSystemEntity.typeSync(
            p.join(bundle.path, 'migrations'),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
    throw FileSystemException(
      'A previous Native build bundled SQLite migrations. Pass '
      '--sqlite-migrations again or remove the bundle explicitly.',
      bundle.path,
    );
  }
  return outputType;
}

/// Serializes publication and restores the previous Native bundle on failure.
Future<String?> replaceNativeBundle({
  required Directory stagedBundle,
  required Directory bundle,
  required File lockFile,
}) async {
  _validateStagedNativeBundle(stagedBundle);
  lockFile.parent.createSync(recursive: true);
  final lock = await lockFile.open(mode: FileMode.append);
  String? warning;
  try {
    await lock.lock(FileLock.blockingExclusive);
    try {
      warning = _replaceNativeBundleLocked(
        stagedBundle: stagedBundle,
        bundle: bundle,
      );
    } finally {
      await lock.unlock();
    }
  } finally {
    await lock.close();
  }
  return warning;
}

String? _replaceNativeBundleLocked({
  required Directory stagedBundle,
  required Directory bundle,
}) {
  _validateStagedNativeBundle(stagedBundle);
  final selectedMigrations =
      FileSystemEntity.typeSync(
        p.join(stagedBundle.path, 'migrations'),
        followLinks: false,
      ) ==
      FileSystemEntityType.directory;
  final previousType = _validateNativeBundleOutput(
    bundle,
    selectedMigrations: selectedMigrations,
  );
  final backup = bundle.parent.createTempSync('.odroe-native-backup-');
  final previous = p.join(backup.path, 'previous');
  var previousMoved = false;
  try {
    if (previousType == FileSystemEntityType.directory) {
      bundle.renameSync(previous);
      previousMoved = true;
    }
    stagedBundle.renameSync(bundle.path);
  } on Object catch (error, stackTrace) {
    try {
      if (previousMoved) {
        Directory(previous).renameSync(bundle.path);
      }
    } on Object catch (restoreError) {
      throw FileSystemException(
        'Could not restore the previous native bundle; recover it from '
        '${backup.path}. Build failure: $error. Restore failure: '
        '$restoreError',
        bundle.parent.path,
      );
    }
    try {
      backup.deleteSync(recursive: true);
    } on Object catch (cleanupError) {
      throw FileSystemException(
        'Native bundle publication failed and the previous bundle was '
        'restored, but temporary backup cleanup failed at ${backup.path}. '
        'Publication failure: $error. Cleanup failure: $cleanupError',
        backup.path,
      );
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
  if (backup.existsSync()) {
    try {
      backup.deleteSync(recursive: true);
    } on Object catch (error) {
      return 'Warning: Native server bundle was published, but the previous '
          'output remains at ${backup.path}: $error';
    }
  }
  return null;
}

void _validateStagedNativeBundle(Directory bundle) {
  final migrationsType = FileSystemEntity.typeSync(
    p.join(bundle.path, 'migrations'),
    followLinks: false,
  );
  if (FileSystemEntity.typeSync(bundle.path, followLinks: false) !=
          FileSystemEntityType.directory ||
      !_isOwnedNativeBundle(bundle) ||
      FileSystemEntity.typeSync(
            p.join(bundle.path, 'bin', _nativeServerExecutableName),
            followLinks: false,
          ) !=
          FileSystemEntityType.file ||
      FileSystemEntity.typeSync(
            p.join(bundle.path, 'lib'),
            followLinks: false,
          ) !=
          FileSystemEntityType.directory ||
      (migrationsType != FileSystemEntityType.notFound &&
          migrationsType != FileSystemEntityType.directory)) {
    throw FileSystemException(
      'Native server staging output is incomplete.',
      bundle.path,
    );
  }
}

bool _isOwnedNativeBundle(Directory bundle) {
  final owner = File(p.join(bundle.path, _nativeBundleOwnerFile));
  return FileSystemEntity.typeSync(owner.path, followLinks: false) ==
          FileSystemEntityType.file &&
      owner.readAsStringSync() == _nativeBundleOwner;
}

/// Rejects a Native bundle when its migration source changed during compile.
void verifySqliteMigrationSnapshot(
  Directory source,
  List<SqliteMigration> expected,
) {
  final current = readSqliteMigrations(source.path);
  if (current.length != expected.length) {
    throw FileSystemException(
      'SQLite migrations changed while the native server was compiled.',
      source.path,
    );
  }
  for (var index = 0; index < current.length; index++) {
    final left = current[index];
    final right = expected[index];
    if (left.version != right.version ||
        left.name != right.name ||
        left.sql != right.sql) {
      throw FileSystemException(
        'SQLite migrations changed while the native server was compiled.',
        source.path,
      );
    }
  }
}

Directory? _resolveSqliteMigrations(
  CliProject project,
  String? relativePath, {
  required String option,
}) {
  if (relativePath == null) return null;
  final resolved = resolveProjectPath(
    project.root,
    relativePath,
    option: option,
  );
  final directory = Directory(p.join(project.root.path, resolved)).absolute;
  if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw FileSystemException(
      '$option must be a regular directory.',
      directory.path,
    );
  }
  return directory;
}

String _cloudflareWorkerSource(String serverFile) =>
    '''
import ${jsonEncode('./$serverFile')};

export default {
  fetch(request, env, context) {
    return globalThis.__odroeFetch(request, env, context);
  },
};
''';

Future<int> _copyPublicAssets(CliProject project, Directory output) async {
  final source = Directory(p.join(project.root.path, 'public')).absolute;
  if (!source.existsSync()) return 0;
  if (p.equals(source.path, output.path) ||
      p.isWithin(source.path, output.path)) {
    throw FileSystemException(
      'Prerender output cannot be inside the public directory.',
      output.path,
    );
  }
  var files = 0;
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    if (entity is Link) continue;
    final relative = p.relative(entity.path, from: source.path);
    final target = p.normalize(p.join(output.path, relative));
    if (!p.isWithin(output.path, target)) continue;
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      final file = File(target);
      file.parent.createSync(recursive: true);
      await entity.copy(file.path);
      files++;
    }
  }
  return files;
}

Future<int> _prerenderBuild(
  CliProject project, {
  required String executable,
  required List<String> arguments,
  required List<String> routes,
  required Directory outputDirectory,
  required Directory reportedOutputDirectory,
  required int concurrency,
  required bool crawlLinks,
  required int maxRoutes,
  required int maxResponseBytes,
  required Duration startupTimeout,
  required Directory? migrationSource,
  required StringSink out,
  required StringSink err,
}) async {
  if (routes.isEmpty) {
    out.writeln('No static routes to prerender.');
    return 0;
  }
  final stateDirectory = await Directory.systemTemp.createTemp(
    'odroe-prerender-state-',
  );
  late final Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      workingDirectory: project.root.path,
      environment: <String, String>{
        for (final entry in Platform.environment.entries)
          if (entry.key != 'ODROE_MIGRATIONS_PATH') entry.key: entry.value,
        'ODROE_HOST': '127.0.0.1',
        'ODROE_PORT': '0',
        'ODROE_WEB_ROOT': '',
        'ODROE_FLUTTER_ORIGIN_FILE': '',
        'ODROE_SQLITE_PATH': p.join(stateDirectory.path, 'app.sqlite3'),
        if (migrationSource != null)
          'ODROE_MIGRATIONS_PATH': migrationSource.path,
      },
      includeParentEnvironment: false,
    );
  } on Object {
    await stateDirectory.delete(recursive: true);
    rethrow;
  }
  final ready = Completer<Uri>();
  final stdoutSubscription = process.stdout
      .transform(systemEncoding.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        final origin = parsePrerenderReadyLine(line);
        if (origin != null && !ready.isCompleted) ready.complete(origin);
      });
  final stderrSubscription = process.stderr
      .transform(systemEncoding.decoder)
      .listen(err.write);
  final stdoutDone = stdoutSubscription.asFuture<void>();
  final stderrDone = stderrSubscription.asFuture<void>();
  unawaited(
    process.exitCode.then((code) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError('Odroe server exited with code $code before listening.'),
        );
      }
    }),
  );

  try {
    final origin = await ready.future.timeout(startupTimeout);
    final rendered = await Prerenderer().render(
      origin: origin,
      routes: routes,
      output: outputDirectory,
      concurrency: concurrency,
      crawlLinks: crawlLinks,
      maxRoutes: maxRoutes,
      maxResponseBytes: maxResponseBytes,
    );
    for (final route in rendered) {
      final outputRelative = p.relative(
        route.file.path,
        from: outputDirectory.path,
      );
      final reportedFile = p.join(reportedOutputDirectory.path, outputRelative);
      final relative = p.relative(reportedFile, from: project.root.path);
      out.writeln(
        'Prerendered ${route.route} -> $relative '
        '(${route.elapsed.inMilliseconds}ms)',
      );
    }
    out.writeln('Prerendered ${rendered.length} routes.');
    return 0;
  } on StateError catch (error) {
    err.writeln(error.message);
    return 1;
  } on Object catch (error) {
    err.writeln(error);
    return 1;
  } finally {
    try {
      await _stopPrerenderServer(
        process,
        stdoutDone,
        stderrDone,
        () => Future.wait<void>(<Future<void>>[
          stdoutSubscription.cancel(),
          stderrSubscription.cancel(),
        ], eagerError: false),
      );
    } finally {
      if (stateDirectory.existsSync()) {
        await stateDirectory.delete(recursive: true);
      }
    }
  }
}

Future<void> _stopPrerenderServer(
  Process process,
  Future<void> stdoutDone,
  Future<void> stderrDone,
  Future<void> Function() cancelOutput,
) async {
  const gracePeriod = Duration(seconds: 10);
  process.kill(ProcessSignal.sigterm);
  try {
    await process.exitCode.timeout(gracePeriod);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode.timeout(gracePeriod);
    } on TimeoutException {
      // Do not let an unresponsive process hold the build open forever.
    }
  }
  try {
    await Future.wait<void>(<Future<void>>[
      stdoutDone,
      stderrDone,
    ], eagerError: false).timeout(gracePeriod);
    return;
  } on Object {
    // A descendant may still own an inherited pipe handle.
  }
  try {
    await cancelOutput().timeout(gracePeriod);
  } on Object {
    // Process output is diagnostic; cleanup must not replace the build result.
  }
}

/// Parses the one readiness line emitted by Odroe's generated native server.
///
/// Arbitrary application logs must never select the prerender origin.
Uri? parsePrerenderReadyLine(String line) {
  final match = RegExp(
    r'^Odroe listening on http://127\.0\.0\.1:([0-9]+)$',
  ).firstMatch(line);
  if (match == null) return null;
  final port = int.tryParse(match.group(1)!);
  if (port == null || port < 1 || port > 65535) return null;
  return Uri(scheme: 'http', host: '127.0.0.1', port: port);
}
