@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/src/cli/development.dart';
import 'package:odroe/src/cli/project.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/dart_command_lock.dart';
import '../support/process.dart';

void main() {
  test(
    'native stop kills a child blocked in restart background drain',
    () async {
      await withDartCommandLock(() async {
        final root = await Directory.systemTemp.createTemp(
          'odroe-native-drain-',
        );
        addTearDown(() => root.delete(recursive: true));
        File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: native_drain_fixture
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  odroe:
    path: ${jsonEncode(Directory.current.absolute.path)}
hooks:
  user_defines:
    sqlite3:
      source: system
      name_windows: winsqlite3
''');
        File(p.join(root.path, 'lib', 'routes', 'route.dart'))
          ..createSync(recursive: true)
          ..writeAsStringSync(
            "import 'package:odroe/router.dart';\n"
            'final route = AppRoute<NoParams, NoSearch, NoData>();\n',
          );
        final source = File(p.join(root.path, 'lib', 'server.dart'))
          ..writeAsStringSync(r'''
import 'dart:async';
import 'dart:io';
import 'package:odroe/server.dart';
Server createServer() {
  File('child-pid').writeAsStringSync('$pid');
  ProcessSignal.sigterm.watch().listen((_) {
    File('graceful-stop').writeAsStringSync('started');
  });
  return Server(routes: const [], middleware: [
    (context, _) {
      context.invocation.waitUntil(Completer<void>().future);
      return ServerResponse.text('background task started');
    },
  ]);
}
''');
        final pubGet = await runTestProcess(
          'flutter',
          const ['pub', 'get', '--offline'],
          workingDirectory: root.path,
          timeout: const Duration(minutes: 1),
        );
        expect(
          pubGet.exitCode,
          0,
          reason: '${pubGet.stdout}\n${pubGet.stderr}',
        );
        final childPidFile = File(p.join(root.path, 'child-pid'));
        addTearDown(() {
          if (childPidFile.existsSync()) {
            Process.killPid(
              int.parse(childPidFile.readAsStringSync()),
              ProcessSignal.sigkill,
            );
          }
        });
        final process = await Process.start(dartExecutable, [
          'run',
          'odroe',
          'dev',
          '--project',
          root.path,
          '--server-only',
          '--port',
          '0',
        ]);
        final logs = StringBuffer();
        final stdout = process.stdout
            .transform(utf8.decoder)
            .listen(logs.write);
        final stderr = process.stderr
            .transform(utf8.decoder)
            .listen(logs.write);
        addTearDown(() async {
          await terminateTestProcess(process, process.exitCode);
          await stdout.cancel();
          await stderr.cancel();
        });
        Future<void> waitUntil(bool Function() ready) async {
          final deadline = DateTime.now().add(const Duration(seconds: 40));
          while (!ready()) {
            if (DateTime.now().isAfter(deadline)) {
              fail('Native fixture not ready.\n$logs');
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }

        await waitUntil(
          () => logs.toString().contains('Odroe listening on http://'),
        );
        final origin = RegExp(
          r'Odroe listening on (http://[^\s]+)',
        ).firstMatch(logs.toString())!.group(1)!;
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final response = await (await client.getUrl(Uri.parse(origin))).close();
        expect(
          await response.transform(utf8.decoder).join(),
          'background task started',
        );
        final childPid = int.parse(childPidFile.readAsStringSync());
        source.writeAsStringSync(
          '${source.readAsStringSync()}\n// trigger restart\n',
        );
        await waitUntil(
          () => File(p.join(root.path, 'graceful-stop')).existsSync(),
        );
        // The old child is draining an actual invocation that never completes.
        // CLI shutdown must escalate before joining that pending restart.
        process.kill(ProcessSignal.sigterm);
        expect(
          await process.exitCode.timeout(const Duration(seconds: 10)),
          0,
          reason: logs.toString(),
        );
        final alive = await Process.run('kill', ['-0', '$childPid']);
        expect(
          alive.exitCode,
          isNot(0),
          reason: 'Background-draining child leaked.',
        );
      });
    },
    skip: Platform.isWindows,
  );

  test('native startup queues edits before the first launcher returns', () async {
    await withDartCommandLock(() async {
      final root = await Directory.systemTemp.createTemp(
        'odroe-native-startup-',
      );
      final children = <Process>[];
      final subscriptions = <StreamSubscription<String>>[];
      final logs = StringBuffer();
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        for (final child in children) {
          await terminateTestProcess(child, child.exitCode);
        }
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        await root.delete(recursive: true);
      });
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: native_startup_fixture
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  odroe:
    path: ${jsonEncode(Directory.current.absolute.path)}
hooks:
  user_defines:
    sqlite3:
      source: system
      name_windows: winsqlite3
''');
      final source = File(p.join(root.path, 'lib', 'shared', 'label.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync("const label = 'startup old';\n");
      File(p.join(root.path, 'lib', 'routes', 'route.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(r'''
import 'package:odroe/document.dart';
import 'package:odroe/router.dart';
import '../shared/label.dart';
final route = AppRoute<NoParams, NoSearch, NoData>().document(
  (_) => const RouteDocument(body: HtmlText(label)),
);
''');
      final pubGet = await runTestProcess(
        'flutter',
        const ['pub', 'get', '--offline'],
        workingDirectory: root.path,
        timeout: const Duration(minutes: 1),
      );
      expect(pubGet.exitCode, 0, reason: '${pubGet.stdout}\n${pubGet.stderr}');
      Future<void> waitForBody(String expected, Duration timeout) async {
        final deadline = DateTime.now().add(timeout);
        while (DateTime.now().isBefore(deadline)) {
          final match = RegExp(
            r'Odroe listening on (http://[^\s]+)',
          ).allMatches(logs.toString()).lastOrNull;
          if (match != null) {
            try {
              final response = await (await client.getUrl(
                Uri.parse(match.group(1)!),
              )).close();
              final body = await response.transform(utf8.decoder).join();
              if (response.statusCode == 200 && body.contains(expected)) return;
            } on Object {
              /* Retry while the child is starting or restarting. */
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        fail('Native startup did not serve $expected.\n$logs');
      }

      final output = StringBuffer();
      final errors = StringBuffer();
      final development = runDevelopment(
        CliProject.fromRoot(root.path),
        host: '127.0.0.1',
        port: 0,
        serverOnly: true,
        flutterArguments: const [],
        sqliteMigrations: null,
        out: output,
        err: errors,
        processStarter:
            (executable, arguments, {required project, environment}) async {
              final child = await Process.start(
                executable,
                arguments,
                workingDirectory: project.root.path,
                environment: environment,
              );
              children.add(child);
              subscriptions.add(
                child.stdout.transform(utf8.decoder).listen(logs.write),
              );
              subscriptions.add(
                child.stderr.transform(utf8.decoder).listen(logs.write),
              );
              if (children.length == 1) {
                // The actual compiler/server already read and served the old source.
                // Keep startup blocked while two real filesystem edits occur.
                await waitForBody('startup old', const Duration(seconds: 40));
                source.writeAsStringSync(
                  "const label = 'startup intermediate';\n",
                );
                await Future<void>.delayed(const Duration(milliseconds: 250));
                source.writeAsStringSync("const label = 'startup latest';\n");
                await Future<void>.delayed(const Duration(milliseconds: 250));
              }
              return child;
            },
      );
      try {
        await waitForBody('startup latest', const Duration(seconds: 60));
        expect(children.length, greaterThan(1));
      } finally {
        children.last.kill(ProcessSignal.sigterm);
        await development.timeout(const Duration(seconds: 15));
      }
      expect(errors.toString(), isEmpty);
    });
  });
}
