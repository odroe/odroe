import 'dart:io';

import 'package:odroe/src/cli/create.dart';

Future<void> main(List<String> inputs) async {
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
            File(inputs[2]).writeAsStringSync('ready');
            await ProcessSignal.sigint.watch().first;
            return 0;
          },
    );
  } on ProcessException catch (error) {
    exitCode = error.errorCode;
  }
}
