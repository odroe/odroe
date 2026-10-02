import 'dart:io';

import 'package:odroe/src/cli/create.dart';

Future<void> main(List<String> inputs) async {
  final interruptInInitializer = inputs.length == 4;
  final initializerSucceeds =
      interruptInInitializer && inputs[3] == 'initializer-success';
  try {
    await createProject(
      directory: inputs[0],
      odroePath: inputs[1],
      platforms: 'web',
      organization: null,
      projectName: 'interrupted_app',
      offline: true,
      out: stdout,
      err: stderr,
      runCommand:
          (
            executable,
            commandArguments, {
            required workingDirectory,
            required out,
            required err,
            environment,
          }) async {
            if (interruptInInitializer) return 0;
            File(inputs[2]).writeAsStringSync('ready');
            await ProcessSignal.sigint.watch().first;
            return 0;
          },
      initialize: interruptInInitializer
          ? (project, out, err) {
              File(inputs[2]).writeAsStringSync('ready');
              out.writeln('Completed initializer output.');
              sleep(const Duration(seconds: 1));
              return initializerSucceeds;
            }
          : null,
    );
  } on ProcessException catch (error) {
    exitCode = error.errorCode;
  }
}
