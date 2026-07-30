import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const _defaultCallbackTimeout = Duration(seconds: 20);
const _defaultTerminationGracePeriod = Duration(seconds: 10);
const _maxCallbackStderrCharacters = 8 * 1024;

/// Loads application-owned prerender locations and merges static routes.
Future<List<String>> loadPrerenderLocations({
  required Directory projectRoot,
  required String packageName,
  required Iterable<String> staticLocations,
  required int maxRoutes,
  String? dartExecutable,
  Duration callbackTimeout = _defaultCallbackTimeout,
  Duration terminationGracePeriod = _defaultTerminationGracePeriod,
}) async {
  if (maxRoutes < 1) {
    throw ArgumentError.value(maxRoutes, 'maxRoutes', 'Must be at least 1.');
  }
  final application = File(
    p.join(projectRoot.path, 'lib', 'prerender.dart'),
  ).absolute;
  final staticRoutes = normalizePrerenderLocations(
    staticLocations.map(Uri.parse),
    maxRoutes: maxRoutes,
  );
  if (!application.existsSync()) {
    return staticRoutes;
  }

  final directory = Directory(
    p.join(projectRoot.path, '.dart_tool', 'odroe'),
  ).absolute..createSync(recursive: true);
  final temporaryId = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
  final bootstrap = File(p.join(directory.path, 'prerender-$temporaryId.dart'));
  final output = File(p.join(directory.path, 'prerender-$temporaryId.json'));
  final source = _bootstrapSource(packageName);

  final processArguments = <String>['run', bootstrap.path];
  final executable = dartExecutable ?? Platform.resolvedExecutable;
  Process? process;
  Future<int>? exitCode;
  Future<void>? stdoutDone;
  Future<void>? stderrDone;
  StreamSubscription<String>? stdoutSubscription;
  StreamSubscription<String>? stderrSubscription;
  var stderrTail = '';
  try {
    bootstrap.writeAsStringSync(source);
    process = await Process.start(
      executable,
      processArguments,
      workingDirectory: projectRoot.path,
      environment: <String, String>{
        ...Platform.environment,
        'ODROE_PRERENDER_OUTPUT': output.path,
        'ODROE_PRERENDER_MAX_ROUTES': '$maxRoutes',
      },
    );
    exitCode = process.exitCode;
    const decoder = Utf8Decoder(allowMalformed: true);
    stdoutSubscription = process.stdout.transform(decoder).listen(null);
    stderrSubscription = process.stderr.transform(decoder).listen((chunk) {
      if (chunk.length >= _maxCallbackStderrCharacters) {
        stderrTail = chunk.substring(
          chunk.length - _maxCallbackStderrCharacters,
        );
        return;
      }
      stderrTail += chunk;
      if (stderrTail.length > _maxCallbackStderrCharacters) {
        stderrTail = stderrTail.substring(
          stderrTail.length - _maxCallbackStderrCharacters,
        );
      }
    });
    stdoutDone = stdoutSubscription.asFuture<void>();
    stderrDone = stderrSubscription.asFuture<void>();
    final code = await _waitForCompletion(exitCode, stdoutDone, stderrDone)
        .timeout(
          callbackTimeout,
          onTimeout: () => throw TimeoutException(
            'Application prerender locations timed out after '
            '${_durationLabel(callbackTimeout)}.',
            callbackTimeout,
          ),
        );
    if (code != 0) {
      final diagnostics = stderrTail.trim();
      throw ProcessException(
        executable,
        processArguments,
        diagnostics.isEmpty
            ? 'Application prerender locations failed.'
            : 'Application prerender locations failed:\n$diagnostics',
        code,
      );
    }

    if (!output.existsSync()) {
      throw const FormatException(
        'Application prerender locations did not produce a manifest.',
      );
    }
    final decoded = jsonDecode(await output.readAsString());
    if (decoded is! Map<String, Object?> ||
        decoded['version'] != 1 ||
        decoded['overflow'] is! bool ||
        decoded['locations'] is! List<Object?>) {
      throw const FormatException(
        'Application prerender manifest has an unsupported shape.',
      );
    }
    if (decoded['overflow']! as bool) {
      throw StateError(
        'Application prerender locations exceed the limit of $maxRoutes.',
      );
    }
    final locations = <Uri>[
      for (final location in staticRoutes) Uri.parse(location),
    ];
    for (final value in decoded['locations']! as List<Object?>) {
      if (value is! String) {
        throw const FormatException(
          'Application prerender locations must be URI strings.',
        );
      }
      locations.add(Uri.parse(value));
    }
    return normalizePrerenderLocations(locations, maxRoutes: maxRoutes);
  } on Object catch (error, stackTrace) {
    if (process case final process?) {
      try {
        await _terminateProcess(process, exitCode!, terminationGracePeriod);
      } on Object {
        // Preserve the failure that required termination.
      }
      await _finishOutput(
        stdoutDone!,
        stderrDone!,
        stdoutSubscription!,
        stderrSubscription!,
        terminationGracePeriod,
      );
    }
    Error.throwWithStackTrace(error, stackTrace);
  } finally {
    if (output.existsSync()) output.deleteSync();
    if (bootstrap.existsSync()) bootstrap.deleteSync();
  }
}

/// Validates, normalizes, deduplicates, and sorts prerender locations.
List<String> normalizePrerenderLocations(
  Iterable<Uri> locations, {
  int? maxRoutes,
}) {
  if (maxRoutes != null && maxRoutes < 1) {
    throw ArgumentError.value(maxRoutes, 'maxRoutes', 'Must be at least 1.');
  }
  final normalized = <String>{};
  for (final location in locations) {
    if (!location.hasAbsolutePath ||
        location.hasScheme ||
        location.hasAuthority ||
        location.hasQuery ||
        location.hasFragment ||
        location.pathSegments.any(
          (segment) => segment == '.' || segment == '..',
        )) {
      throw FormatException(
        'Prerender location must be an absolute local path without query or '
        'fragment: $location',
      );
    }
    var value = location.toString();
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    normalized.add(value);
    if (maxRoutes != null && normalized.length > maxRoutes) {
      throw StateError('Prerender locations exceed the limit of $maxRoutes.');
    }
  }
  return normalized.toList(growable: false)..sort();
}

Future<void> _terminateProcess(
  Process process,
  Future<int> exitCode,
  Duration gracePeriod,
) async {
  process.kill(ProcessSignal.sigterm);
  try {
    await exitCode.timeout(gracePeriod);
    return;
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
  }
  await exitCode.timeout(gracePeriod);
}

Future<int> _waitForCompletion(
  Future<int> exitCode,
  Future<void> stdoutDone,
  Future<void> stderrDone,
) async {
  final code = await exitCode;
  await _drainOutput(stdoutDone, stderrDone);
  return code;
}

Future<void> _finishOutput(
  Future<void> stdoutDone,
  Future<void> stderrDone,
  StreamSubscription<String> stdoutSubscription,
  StreamSubscription<String> stderrSubscription,
  Duration gracePeriod,
) async {
  try {
    await _drainOutput(stdoutDone, stderrDone).timeout(gracePeriod);
    return;
  } on Object {
    // Stop listening when a descendant keeps inherited pipe handles open.
  }
  try {
    await Future.wait<void>(<Future<void>>[
      stdoutSubscription.cancel(),
      stderrSubscription.cancel(),
    ], eagerError: false).timeout(gracePeriod);
  } on Object {
    // Preserve the callback failure even if pipe cancellation misbehaves.
  }
}

Future<void> _drainOutput(Future<void> stdoutDone, Future<void> stderrDone) =>
    Future.wait<void>(<Future<void>>[
      stdoutDone,
      stderrDone,
    ], eagerError: false);

String _durationLabel(Duration duration) {
  if (duration.inMilliseconds.remainder(1000) == 0) {
    return '${duration.inSeconds} seconds';
  }
  return '${duration.inMilliseconds} milliseconds';
}

String _bootstrapSource(String packageName) =>
    '''
// Generated by Odroe. Do not edit.
import 'dart:convert';
import 'dart:io';

import 'package:$packageName/prerender.dart' as app;

Future<void> main() async {
  final output = Platform.environment['ODROE_PRERENDER_OUTPUT'];
  if (output == null || output.isEmpty) {
    throw StateError('ODROE_PRERENDER_OUTPUT is required.');
  }
  final maxRoutes = int.parse(
    Platform.environment['ODROE_PRERENDER_MAX_ROUTES'] ?? '',
  );
  final Iterable<Uri> locations = await app.prerenderLocations();
  final values = <String, String>{};
  var overflow = false;
  for (final location in locations) {
    values.putIfAbsent(_manifestKey(location), () => location.toString());
    if (values.length > maxRoutes) {
      overflow = true;
      break;
    }
  }
  await File(output).writeAsString(
    jsonEncode(<String, Object?>{
      'version': 1,
      'overflow': overflow,
      'locations': values.values.toList(growable: false),
    }),
    flush: true,
  );
}

String _manifestKey(Uri location) {
  if (!location.hasAbsolutePath ||
      location.hasScheme ||
      location.hasAuthority ||
      location.hasQuery ||
      location.hasFragment ||
      location.pathSegments.any(
        (segment) => segment == '.' || segment == '..',
      )) {
    return location.toString();
  }
  var value = location.toString();
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}
''';
