import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/database_postgres.dart';
import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart' as pg;

/// One disposable PostgreSQL process used by integration tests.
final class PostgresTestCluster {
  PostgresTestCluster._(this._root, this._process, this.port, this._logs);

  /// PostgreSQL initialization binary resolved from configuration or PATH.
  static final String? initdbPath = _resolveBinary('initdb');

  /// PostgreSQL server binary resolved from configuration or PATH.
  static final String? postgresPath = _resolveBinary('postgres');

  /// Explains why PostgreSQL integration tests cannot run, if applicable.
  static String? get unavailableReason {
    final initdb = initdbPath;
    final server = postgresPath;
    if (initdb == null || server == null) {
      return 'PostgreSQL initdb and postgres must be available on PATH or in '
          'ODROE_POSTGRES_BIN_DIR.';
    }
    late final ProcessResult serverVersion;
    late final ProcessResult initdbVersion;
    try {
      serverVersion = Process.runSync(server, const <String>['--version']);
      initdbVersion = Process.runSync(initdb, const <String>['--version']);
    } on ProcessException {
      return 'PostgreSQL initdb and postgres must be executable.';
    }
    final serverMajor = _majorVersion(serverVersion.stdout);
    final initdbMajor = _majorVersion(initdbVersion.stdout);
    if (serverVersion.exitCode != 0 ||
        initdbVersion.exitCode != 0 ||
        serverMajor == null ||
        initdbMajor == null ||
        serverMajor != initdbMajor ||
        serverMajor < 14) {
      return 'PostgreSQL initdb and postgres must have the same supported '
          'major version (14 or newer).';
    }
    return null;
  }

  final Directory _root;
  final Process _process;
  final StringBuffer _logs;

  /// Random loopback port used by this cluster.
  final int port;

  /// Creates, initializes, and starts a disposable cluster.
  static Future<PostgresTestCluster> start() async {
    final root = await Directory.systemTemp.createTemp('odroe-postgres-test-');
    final data = Directory('${root.path}/data');
    final initialized = await Process.run(initdbPath!, <String>[
      '-D',
      data.path,
      '-A',
      'trust',
      '-U',
      'postgres',
      '--no-locale',
      '--encoding=UTF8',
    ], workingDirectory: root.path);
    if (initialized.exitCode != 0) {
      await root.delete(recursive: true);
      throw StateError(
        'initdb failed with exit code ${initialized.exitCode}: '
        '${initialized.stderr}',
      );
    }

    final port = await _freeLoopbackPort();
    late final Process process;
    try {
      process = await Process.start(postgresPath!, <String>[
        '-D',
        data.path,
        '-h',
        InternetAddress.loopbackIPv4.address,
        '-p',
        '$port',
        '-k',
        root.path,
        '-F',
      ], workingDirectory: root.path);
    } on Object {
      await root.delete(recursive: true);
      rethrow;
    }
    final logs = StringBuffer();
    process.stdout.transform(utf8.decoder).listen(logs.write);
    process.stderr.transform(utf8.decoder).listen(logs.write);

    final cluster = PostgresTestCluster._(root, process, port, logs);
    try {
      await cluster._waitUntilReady();
      return cluster;
    } on Object {
      await cluster.close();
      rethrow;
    }
  }

  /// Opens an Odroe-owned connection to the temporary cluster.
  Future<PostgresDatabase> openDatabase() {
    return PostgresDatabase.open(
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      database: 'postgres',
      username: 'postgres',
      settings: const pg.ConnectionSettings(
        sslMode: pg.SslMode.disable,
        connectTimeout: Duration(seconds: 1),
      ),
    );
  }

  /// Opens a caller-owned raw connection to the temporary cluster.
  Future<pg.Connection> openConnection() {
    return pg.Connection.open(
      pg.Endpoint(
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        database: 'postgres',
        username: 'postgres',
      ),
      settings: const pg.ConnectionSettings(
        sslMode: pg.SslMode.disable,
        connectTimeout: Duration(seconds: 1),
      ),
    );
  }

  /// PostgreSQL URL for the temporary cluster.
  String get connectionUrl =>
      'postgresql://postgres@${InternetAddress.loopbackIPv4.address}:'
      '$port/postgres?sslmode=disable';

  /// Stops the server and removes its temporary files.
  Future<void> close() async {
    _process.kill(ProcessSignal.sigterm);
    try {
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      await _process.exitCode;
    } finally {
      if (await _root.exists()) {
        await _root.delete(recursive: true);
      }
    }
  }

  Future<void> _waitUntilReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final connection = await openConnection();
        await connection.close();
        return;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    throw StateError('PostgreSQL did not become ready:\n$_logs');
  }
}

Future<int> _freeLoopbackPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

String? _resolveBinary(String name) {
  final configured = Platform.environment['ODROE_POSTGRES_BIN_DIR'];
  if (configured != null && configured.isNotEmpty) {
    final candidate = File(
      p.join(configured, Platform.isWindows ? '$name.exe' : name),
    );
    return candidate.existsSync() ? candidate.absolute.path : null;
  }

  final path = Platform.environment['PATH'];
  if (path == null || path.isEmpty) return null;
  final executable = Platform.isWindows ? '$name.exe' : name;
  for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
    if (directory.isEmpty) continue;
    final candidate = File(p.join(directory, executable));
    if (candidate.existsSync()) return candidate.absolute.path;
  }
  return null;
}

int? _majorVersion(Object? output) {
  final match = RegExp(
    r'PostgreSQL\)?\s+(\d+)(?:\.|$)',
  ).firstMatch(output.toString());
  return match == null ? null : int.tryParse(match.group(1)!);
}
