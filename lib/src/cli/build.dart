import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/server_io.dart';
import 'package:path/path.dart' as p;

import '../atomic_write.dart';
import '../database_sqlite/migration.dart';
import '../filesystem_case.dart';
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
}) => _withBuildLock(
  project,
  out,
  () => _runBuildLocked(
    project,
    serverOnly: serverOnly,
    buildServer: buildServer,
    serverTarget: serverTarget,
    serverArtifact: serverArtifact,
    sqliteMigrations: sqliteMigrations,
    prerender: prerender,
    prerenderOutput: prerenderOutput,
    prerenderConcurrency: prerenderConcurrency,
    prerenderCrawl: prerenderCrawl,
    prerenderMaxRoutes: prerenderMaxRoutes,
    prerenderMaxResponseBytes: prerenderMaxResponseBytes,
    flutterArguments: flutterArguments,
    out: out,
    err: err,
  ),
);

Future<int> _runBuildLocked(
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
  final publicSource = Directory(p.join(project.root.path, 'public'));
  if (FileSystemEntity.typeSync(publicSource.path, followLinks: false) ==
      FileSystemEntityType.link) {
    err.writeln('Public assets cannot be a symbolic link.');
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
  final flutterWebOutput = flutterTarget == 'web' && flutterOutputs.isNotEmpty
      ? flutterOutputs.single
      : null;
  if (flutterWebOutput != null &&
      !_pathIsWithin(
        _realPathForOverlap(p.join(project.root.path, 'build')),
        flutterWebOutput.path,
      )) {
    err.writeln('Flutter Web output must resolve inside build/.');
    return 64;
  }
  if (flutterWebOutput != null && !_replaceableDirectory(flutterWebOutput)) {
    err.writeln('Flutter Web output must be a regular directory or not exist.');
    return 64;
  }
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
    if (!_replaceableDirectory(outputDirectory)) {
      err.writeln(
        '--prerender-output must be a regular directory or not exist.',
      );
      return 64;
    }
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
    for (final flutterOutput in flutterOutputs) {
      if (_pathsOverlap(flutterOutput.path, outputDirectory.path) &&
          !_pathsEqual(flutterOutput.path, outputDirectory.path)) {
        err.writeln(
          'Flutter build output and --prerender-output must either match or '
          'not overlap.',
        );
        return 64;
      }
    }
  }
  final selectedOutputs = <String>[
    ...serverOutputs,
    for (final output in flutterOutputs) output.path,
    if (shouldPrerender) outputDirectory.path,
  ];
  if (selectedOutputs.any((path) => _pathsOverlap(path, publicSource.path))) {
    err.writeln('Build outputs and public assets must not overlap.');
    return 64;
  }
  if (shouldPrerender && !inspectedRoutes.hasFlutter) {
    _validatePrerenderOwnership(project, outputDirectory);
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
  _NativeBundleStage? nativeStage;
  Directory? cloudflareStage;
  Directory? flutterWebStage;
  Directory? prerenderStage;
  var prerenderSharesFlutterOutput = false;
  try {
    if (buildServer) {
      if (serverTarget == ServerBuildTarget.native) {
        final result = await _stageNativeServer(
          project,
          Directory(artifactPath!),
          migrationSource: migrationSource,
          out: out,
        );
        if (result.code != 0) return result.code;
        nativeStage = result.stage!;
      } else {
        final artifact = File(artifactPath!);
        artifact.parent.createSync(recursive: true);
        cloudflareStage = artifact.parent.createTempSync(
          '.odroe-worker-stage-',
        );
        final code = await buildCloudflareServer(
          project,
          artifact: File(
            p.join(cloudflareStage.path, p.basename(artifact.path)),
          ),
          out: out,
          report: false,
        );
        if (code != 0) return code;
      }
    }
    if (!serverOnly && flutterArguments.isNotEmpty) {
      final effectiveFlutterArguments = flutterWebOutput == null
          ? flutterArguments
          : _flutterArgumentsWithOutput(
              flutterArguments,
              (flutterWebStage = _siblingTemporaryDirectory(
                flutterWebOutput,
                'staging',
              )).path,
            );
      final flutter = await startProjectProcess('flutter', <String>[
        'build',
        ...effectiveFlutterArguments,
      ], project: project);
      final code = await flutter.exitCode;
      if (code != 0) return code;
    }
    if (shouldPrerender) {
      prerenderSharesFlutterOutput =
          flutterWebOutput != null &&
          flutterWebStage != null &&
          sameBuildDirectory(flutterWebOutput, outputDirectory);
      if (flutterWebOutput != null &&
          !prerenderSharesFlutterOutput &&
          _realPathsOverlap(flutterWebOutput.path, outputDirectory.path)) {
        err.writeln(
          'Flutter build output and --prerender-output must either match or '
          'not overlap.',
        );
        return 64;
      }
      final renderDirectory = prerenderSharesFlutterOutput
          ? flutterWebStage
          : (prerenderStage = _siblingTemporaryDirectory(
              outputDirectory,
              'staging',
            ));
      renderDirectory.createSync(recursive: true);
      final assets = await _copyPublicAssets(project, renderDirectory);
      if (assets > 0) out.writeln('Copied $assets public assets.');
      final prerenderFromSource = nativeStage == null;
      final prerenderExecutable = prerenderFromSource
          ? Platform.resolvedExecutable
          : p.join(nativeStage.bundle.path, 'bin', _nativeServerExecutableName);
      final prerenderArguments = prerenderFromSource
          ? <String>['run', project.bootstrap.path]
          : const <String>['--odroe-internal-prerender'];
      final prerenderMigrationSource =
          migrationSource != null && nativeStage != null
          ? Directory(p.join(nativeStage.bundle.path, 'migrations'))
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
      if (!inspectedRoutes.hasFlutter) {
        File(
          p.join(renderDirectory.path, '.odroe-prerender'),
        ).writeAsStringSync(_prerenderOwnership(project));
      }
    }
    if (nativeStage != null) {
      final stagedPrerenderOutput = shouldPrerender
          ? (prerenderSharesFlutterOutput ? flutterWebStage : prerenderStage)
          : null;
      if (flutterWebStage != null || stagedPrerenderOutput != null) {
        installNativeWeb(
          nativeStage.bundle,
          flutterOutput: flutterWebStage,
          prerenderOutput: stagedPrerenderOutput,
        );
      }
    }
    _publishBuildOutputs(
      project,
      webOutputs: <BuildDirectoryPublication>[
        if (flutterWebStage != null)
          (source: flutterWebStage, target: flutterWebOutput!),
        if (prerenderStage != null)
          (source: prerenderStage, target: outputDirectory),
      ],
      cloudflareOutputs: cloudflareStage == null
          ? const <BuildFilePublication>[]
          : _cloudflareOutputs(cloudflareStage, File(artifactPath!)),
      nativeStage: nativeStage,
      nativeBundle: nativeStage == null ? null : Directory(artifactPath!),
      out: out,
    );
    return 0;
  } finally {
    final temporaryDirectory = nativeStage?.temporaryDirectory;
    if (temporaryDirectory != null && temporaryDirectory.existsSync()) {
      try {
        temporaryDirectory.deleteSync(recursive: true);
      } on FileSystemException catch (error) {
        out.writeln(
          'Warning: Native build staging remains at '
          '${temporaryDirectory.path}: ${error.message}',
        );
      }
    }
    for (final stage in <Directory?>[
      cloudflareStage,
      flutterWebStage,
      prerenderStage,
    ]) {
      if (stage != null && stage.existsSync()) {
        try {
          stage.deleteSync(recursive: true);
        } on FileSystemException catch (error) {
          out.writeln(
            'Warning: Build staging remains at '
            '${stage.path}: ${error.message}',
          );
        }
      }
    }
  }
}

Future<T> _withBuildLock<T>(
  CliProject project,
  StringSink out,
  Future<T> Function() build,
) async {
  final lockFile = File(
    p.join(project.root.path, '.dart_tool', 'odroe', 'build.lock'),
  );
  lockFile.parent.createSync(recursive: true);
  final lock = await lockFile.open(mode: FileMode.append);
  var locked = false;
  try {
    await lock.lock(FileLock.blockingExclusive);
    locked = true;
    return await build();
  } finally {
    if (locked) {
      try {
        await lock.unlock();
      } on FileSystemException catch (error) {
        out.writeln(
          'Warning: Could not unlock ${lockFile.path}: ${error.message}',
        );
      }
    }
    try {
      await lock.close();
    } on FileSystemException catch (error) {
      out.writeln(
        'Warning: Could not close ${lockFile.path}: ${error.message}',
      );
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

List<String> _flutterArgumentsWithOutput(
  List<String> arguments,
  String output,
) {
  const options = <String>['--output', '--output-dir', '-o'];
  final rewritten = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (options.contains(argument)) {
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('-')) {
        throw FormatException('$argument requires a directory.');
      }
      index++;
      continue;
    }
    final option = options
        .where((option) => argument.startsWith('$option='))
        .firstOrNull;
    if (option != null) {
      if (argument.length == option.length + 1) {
        throw FormatException('$option requires a directory.');
      }
      continue;
    }
    rewritten.add(argument);
  }
  return <String>[...rewritten, '--output', output];
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
  final ignoreCase = usesCaseInsensitivePaths(left);
  final normalizedLeft = _pathForComparison(
    _realPathForOverlap(left),
    ignoreCase: ignoreCase,
  );
  final normalizedRight = _pathForComparison(
    _realPathForOverlap(right),
    ignoreCase: ignoreCase,
  );
  return p.equals(normalizedLeft, normalizedRight) ||
      p.isWithin(normalizedLeft, normalizedRight) ||
      p.isWithin(normalizedRight, normalizedLeft);
}

bool _pathsEqual(String left, String right) {
  final ignoreCase = usesCaseInsensitivePaths(left);
  return p.equals(
    _pathForComparison(left, ignoreCase: ignoreCase),
    _pathForComparison(right, ignoreCase: ignoreCase),
  );
}

String _pathForComparison(String path, {required bool ignoreCase}) {
  final normalized = p.normalize(path);
  return ignoreCase ? normalized.toLowerCase() : normalized;
}

/// Reports whether two build directories denote the same filesystem location.
bool sameBuildDirectory(Directory left, Directory right) {
  if (_pathsEqual(left.absolute.path, right.absolute.path)) {
    return true;
  }
  if (FileSystemEntity.typeSync(left.path, followLinks: false) !=
          FileSystemEntityType.directory ||
      FileSystemEntity.typeSync(right.path, followLinks: false) !=
          FileSystemEntityType.directory) {
    return false;
  }
  return FileSystemEntity.identicalSync(left.path, right.path);
}

bool _realPathsOverlap(String left, String right) =>
    _pathsOverlap(_realPathForOverlap(left), _realPathForOverlap(right));

bool _pathIsWithin(String parent, String child) {
  final ignoreCase = usesCaseInsensitivePaths(parent);
  return p.isWithin(
    _pathForComparison(parent, ignoreCase: ignoreCase),
    _pathForComparison(child, ignoreCase: ignoreCase),
  );
}

Directory _siblingTemporaryDirectory(Directory target, String suffix) {
  final id = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
  return Directory(
    p.join(target.parent.path, '.${p.basename(target.path)}.odroe-$suffix-$id'),
  );
}

bool _replaceableDirectory(Directory target) {
  final type = FileSystemEntity.typeSync(target.path, followLinks: false);
  return type == FileSystemEntityType.notFound ||
      type == FileSystemEntityType.directory;
}

/// One staged directory and its managed final build output.
typedef BuildDirectoryPublication = ({Directory source, Directory target});
typedef _DirectoryReplacement = ({
  Directory target,
  Directory backup,
  bool hadPrevious,
});

void _publishBuildOutputs(
  CliProject project, {
  required List<BuildDirectoryPublication> webOutputs,
  required List<BuildFilePublication> cloudflareOutputs,
  required _NativeBundleStage? nativeStage,
  required Directory? nativeBundle,
  required StringSink out,
}) {
  if (nativeStage != null) _validateNativeStage(nativeStage);
  final nativeWarning = replaceBuildDirectories<String?>(
    outputs: webOutputs,
    commit: () => replaceBuildFiles<String?>(
      outputs: cloudflareOutputs,
      commit: () => nativeStage == null
          ? null
          : _publishNativeServer(nativeStage, nativeBundle!),
      out: out,
    ),
    out: out,
  );
  if (nativeWarning != null) out.writeln(nativeWarning);
  if (cloudflareOutputs.isNotEmpty) {
    _reportCloudflareServer(project, cloudflareOutputs.last.target, out);
  }
  if (nativeStage != null) {
    _reportNativeServer(project, nativeStage, nativeBundle!, out);
  }
}

/// One staged file and its managed final build output.
typedef BuildFilePublication = ({File source, File target});

List<BuildFilePublication> _cloudflareOutputs(Directory stage, File artifact) =>
    <BuildFilePublication>[
      (
        source: File(p.join(stage.path, p.basename(artifact.path))),
        target: artifact,
      ),
      (
        source: File(p.join(stage.path, '${p.basename(artifact.path)}.deps')),
        target: File('${artifact.path}.deps'),
      ),
      (
        source: File(p.join(stage.path, 'worker.mjs')),
        target: File(p.join(artifact.parent.path, 'worker.mjs')),
      ),
    ];

/// Publishes only the selected files, preserving unrelated sibling assets.
/// A failed publication or [commit] restores every previous selected file.
T replaceBuildFiles<T>({
  required List<BuildFilePublication> outputs,
  required T Function() commit,
  required StringSink out,
}) {
  final replacements = <({File target, File backup, bool hadPrevious})>[];
  late T result;
  try {
    for (final output in outputs) {
      final type = FileSystemEntity.typeSync(
        output.target.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw FileSystemException(
          'Worker output must be a regular file.',
          output.target.path,
        );
      }
      if (FileSystemEntity.typeSync(output.source.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw FileSystemException(
          'Staged Worker output must be a regular file.',
          output.source.path,
        );
      }
      final backup = File(
        '${output.target.path}.odroe-backup-${pid}_${DateTime.now().microsecondsSinceEpoch}',
      );
      final hadPrevious = type == FileSystemEntityType.file;
      if (hadPrevious) output.target.renameSync(backup.path);
      // Record the backup before moving the staged file so this operation's
      // failure also participates in rollback.
      replacements.add((
        target: output.target,
        backup: backup,
        hadPrevious: hadPrevious,
      ));
      output.source.renameSync(output.target.path);
    }
    result = commit();
  } on Object catch (error, stackTrace) {
    for (final replacement in replacements.reversed) {
      try {
        if (replacement.target.existsSync()) replacement.target.deleteSync();
        if (replacement.hadPrevious) {
          replacement.backup.renameSync(replacement.target.path);
        }
      } on Object catch (rollbackError) {
        out.writeln(
          'Warning: Could not restore Worker output ${replacement.target.path}; previous output remains at ${replacement.backup.path}: $rollbackError',
        );
      }
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
  for (final replacement in replacements) {
    if (!replacement.backup.existsSync()) continue;
    try {
      replacement.backup.deleteSync();
    } on Object catch (error) {
      out.writeln(
        'Warning: Worker output was published, but previous output remains at ${replacement.backup.path}: $error',
      );
    }
  }
  return result;
}

void _reportCloudflareServer(CliProject project, File worker, StringSink out) {
  out.writeln(
    'Built Cloudflare Worker -> ${p.relative(worker.path, from: project.root.path)}',
  );
}

/// Replaces related build directories and restores all of them if [commit]
/// fails. This CLI helper is not exported from a product entrypoint.
T replaceBuildDirectories<T>({
  required List<BuildDirectoryPublication> outputs,
  required T Function() commit,
  required StringSink out,
}) {
  final replacements = <_DirectoryReplacement>[];
  late T result;
  try {
    for (final output in outputs) {
      replacements.add(_replaceDirectory(output.source, output.target, out));
    }
    result = commit();
  } on Object catch (error, stackTrace) {
    final rollbackErrors = <Object>[];
    for (final replacement in replacements.reversed) {
      try {
        final warning = _restoreDirectory(replacement);
        if (warning != null) out.writeln(warning);
      } on Object catch (rollbackError) {
        rollbackErrors.add(rollbackError);
      }
    }
    if (rollbackErrors.isNotEmpty) {
      out.writeln(
        'Warning: Previous Web outputs could not be fully restored. '
        'Retained backup paths: ${rollbackErrors.join('; ')}',
      );
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
  for (final replacement in replacements) {
    final warning = _discardDirectoryBackup(replacement);
    if (warning != null) out.writeln(warning);
  }
  return result;
}

_DirectoryReplacement _replaceDirectory(
  Directory source,
  Directory target,
  StringSink out,
) {
  final targetType = FileSystemEntity.typeSync(target.path, followLinks: false);
  if (targetType != FileSystemEntityType.notFound &&
      targetType != FileSystemEntityType.directory) {
    throw FileSystemException(
      'Web output must be a regular directory.',
      target.path,
    );
  }
  final backup = _siblingTemporaryDirectory(target, 'backup');
  final hadPrevious = targetType == FileSystemEntityType.directory;
  var movedTarget = false;
  try {
    if (hadPrevious) {
      target.renameSync(backup.path);
      movedTarget = true;
    }
    source.renameSync(target.path);
  } on Object catch (error, stackTrace) {
    if (movedTarget && !target.existsSync() && backup.existsSync()) {
      try {
        backup.renameSync(target.path);
      } on FileSystemException catch (restoreError) {
        out.writeln(
          'Warning: Previous output remains at ${backup.path}: '
          '${restoreError.message}',
        );
      }
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
  return (target: target, backup: backup, hadPrevious: hadPrevious);
}

String? _restoreDirectory(_DirectoryReplacement replacement) {
  final published = _siblingTemporaryDirectory(replacement.target, 'rollback');
  var movedPublished = false;
  try {
    if (replacement.target.existsSync()) {
      replacement.target.renameSync(published.path);
      movedPublished = true;
    }
    if (replacement.hadPrevious) {
      replacement.backup.renameSync(replacement.target.path);
    }
  } on Object catch (error) {
    Object? recoveryError;
    if (!replacement.target.existsSync() &&
        movedPublished &&
        published.existsSync()) {
      try {
        published.renameSync(replacement.target.path);
      } on Object catch (restorePublishedError) {
        recoveryError = restorePublishedError;
      }
    }
    throw FileSystemException(
      'Could not restore the previous Web output; recover it from '
      '${replacement.backup.path}. Rollback failure: $error'
      '${recoveryError == null ? '' : '. Recovery failure: $recoveryError'}',
      replacement.target.path,
    );
  }
  if (published.existsSync()) {
    try {
      published.deleteSync(recursive: true);
    } on Object catch (error) {
      return 'Warning: Failed Web output remains at ${published.path}: $error';
    }
  }
  return null;
}

String? _discardDirectoryBackup(_DirectoryReplacement replacement) {
  if (!replacement.backup.existsSync()) return null;
  try {
    replacement.backup.deleteSync(recursive: true);
  } on Object catch (error) {
    return 'Warning: Web output was published, but the previous output '
        'remains at ${replacement.backup.path}: $error';
  }
  return null;
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

/// Compiles and transactionally replaces the Cloudflare Worker file family.
///
/// Compilation happens beside the final artifact. A failed compile leaves the
/// previous runnable Worker untouched, which lets local development keep its
/// last-known-good server while the source is being fixed.
Future<int> buildCloudflareServer(
  CliProject project, {
  required File artifact,
  required StringSink out,
  Future<void>? cancelled,
  bool report = true,
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

    final worker = File(p.join(staging.path, 'worker.mjs'));
    writeStringIfChanged(
      worker,
      _cloudflareWorkerSource(p.basename(artifact.path)),
    );
    replaceBuildFiles<void>(
      outputs: _cloudflareOutputs(staging, artifact),
      commit: () {},
      out: out,
    );
    if (report) {
      _reportCloudflareServer(
        project,
        File(p.join(artifact.parent.path, 'worker.mjs')),
        out,
      );
    }
    return 0;
  } finally {
    if (staging.existsSync()) {
      try {
        staging.deleteSync(recursive: true);
      } on FileSystemException catch (error) {
        out.writeln(
          'Warning: Worker build staging remains at ${staging.path}: ${error.message}',
        );
      }
    }
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

final class _NativeBundleStage {
  const _NativeBundleStage({
    required this.temporaryDirectory,
    required this.bundle,
    required this.migrationSource,
    required this.migrations,
  });

  final Directory temporaryDirectory;
  final Directory bundle;
  final Directory? migrationSource;
  final List<SqliteMigration>? migrations;
}

Future<({int code, _NativeBundleStage? stage})> _stageNativeServer(
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
  var keepStaging = false;
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
    final process =
        await startProjectProcess(Platform.resolvedExecutable, <String>[
          'build',
          'cli',
          '--target',
          project.bootstrap.path,
          '--output',
          buildOutput.path,
        ], project: project);
    final code = await process.exitCode;
    if (code != 0) return (code: code, stage: null);
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
    keepStaging = true;
    return (
      code: 0,
      stage: _NativeBundleStage(
        temporaryDirectory: staging,
        bundle: stagedBundle,
        migrationSource: migrationSource,
        migrations: migrations,
      ),
    );
  } finally {
    if (!keepStaging && staging.existsSync()) {
      try {
        staging.deleteSync(recursive: true);
      } on FileSystemException catch (error) {
        out.writeln(
          'Warning: Native build staging remains at ${staging.path}: '
          '${error.message}',
        );
      }
    }
  }
}

void _validateNativeStage(_NativeBundleStage stage) {
  if (stage.migrationSource != null) {
    verifySqliteMigrationSnapshot(stage.migrationSource!, stage.migrations!);
  }
}

String? _publishNativeServer(_NativeBundleStage stage, Directory bundle) {
  _validateNativeStage(stage);
  return _replaceNativeBundleLocked(stagedBundle: stage.bundle, bundle: bundle);
}

void _reportNativeServer(
  CliProject project,
  _NativeBundleStage stage,
  Directory bundle,
  StringSink out,
) {
  out.writeln(
    'Built Native server bundle -> '
    '${p.relative(bundle.path, from: project.root.path)}',
  );
  if (stage.migrations != null) {
    out.writeln(
      'Bundled ${stage.migrations!.length} SQLite migrations -> '
      '${p.relative(p.join(bundle.path, 'migrations'), from: project.root.path)}',
    );
  }
}

/// Layers verified Web outputs into an unpublished Native bundle.
///
/// This lives under `src/cli`; it is not a package product entrypoint.
void installNativeWeb(
  Directory bundle, {
  required Directory? flutterOutput,
  required Directory? prerenderOutput,
}) {
  final destination = Directory(p.join(bundle.path, 'build', 'web'));
  if (FileSystemEntity.typeSync(destination.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw FileSystemException(
      'Native Web staging output already exists.',
      destination.path,
    );
  }
  final sharesFlutterOutput =
      flutterOutput != null &&
      prerenderOutput != null &&
      sameBuildDirectory(flutterOutput, prerenderOutput);
  if (flutterOutput != null &&
      prerenderOutput != null &&
      !sharesFlutterOutput &&
      _realPathsOverlap(flutterOutput.path, prerenderOutput.path)) {
    throw FileSystemException(
      'Flutter Web and prerender outputs must not overlap.',
      prerenderOutput.path,
    );
  }
  if (flutterOutput != null) {
    _copyBuildTree(flutterOutput, destination, label: 'Flutter Web output');
  }
  if (prerenderOutput != null && !sharesFlutterOutput) {
    _copyBuildTree(prerenderOutput, destination, label: 'prerender output');
  }
  if (FileSystemEntity.typeSync(destination.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw FileSystemException(
      'Native Web staging output is incomplete.',
      destination.path,
    );
  }
}

void _copyBuildTree(
  Directory source,
  Directory destination, {
  required String label,
}) {
  if (FileSystemEntity.typeSync(source.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw FileSystemException('$label is missing.', source.path);
  }
  if (_pathsOverlap(source.absolute.path, destination.absolute.path)) {
    throw FileSystemException(
      '$label must not overlap Native Web staging output.',
      source.path,
    );
  }
  final entities = source.listSync(recursive: true, followLinks: false);
  for (final entity in entities) {
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw FileSystemException(
        '$label must not contain symbolic links.',
        entity.path,
      );
    }
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException(
        '$label contains an unsupported file type.',
        entity.path,
      );
    }
  }
  final destinationType = FileSystemEntity.typeSync(
    destination.path,
    followLinks: false,
  );
  if (destinationType == FileSystemEntityType.notFound) {
    destination.createSync(recursive: true);
  } else if (destinationType != FileSystemEntityType.directory) {
    throw FileSystemException(
      'Native Web staging output must be a regular directory.',
      destination.path,
    );
  }
  for (final entity in entities) {
    final relative = p.relative(entity.path, from: source.path);
    final target = p.join(destination.path, relative);
    switch (FileSystemEntity.typeSync(entity.path, followLinks: false)) {
      case FileSystemEntityType.directory:
        final targetType = FileSystemEntity.typeSync(
          target,
          followLinks: false,
        );
        if (targetType == FileSystemEntityType.notFound) {
          Directory(target).createSync(recursive: true);
        } else if (targetType != FileSystemEntityType.directory) {
          throw FileSystemException(
            '$label conflicts with another Web build layer.',
            entity.path,
          );
        }
      case FileSystemEntityType.file:
        File(target).parent.createSync(recursive: true);
        final targetType = FileSystemEntity.typeSync(
          target,
          followLinks: false,
        );
        if (targetType != FileSystemEntityType.notFound &&
            targetType != FileSystemEntityType.file) {
          throw FileSystemException(
            '$label conflicts with another Web build layer.',
            entity.path,
          );
        }
        File(entity.path).copySync(target);
      default:
        throw StateError('Validated Web tree contains an unsupported type.');
    }
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
  void Function()? validateBeforePublish,
}) async {
  _validateStagedNativeBundle(stagedBundle);
  lockFile.parent.createSync(recursive: true);
  final lock = await lockFile.open(mode: FileMode.append);
  String? warning;
  try {
    await lock.lock(FileLock.blockingExclusive);
    try {
      validateBeforePublish?.call();
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

String _prerenderOwnership(CliProject project) =>
    'odroe-prerender-v1:${project.packageName}\n';

void _validatePrerenderOwnership(CliProject project, Directory output) {
  if (!output.existsSync()) return;
  final marker = File(p.join(output.path, '.odroe-prerender'));
  if (FileSystemEntity.typeSync(marker.path, followLinks: false) !=
          FileSystemEntityType.file ||
      marker.readAsStringSync() != _prerenderOwnership(project)) {
    throw const FormatException(
      'Existing document output is not owned by this project. '
      'Choose a new --prerender-output inside build/.',
    );
  }
}
