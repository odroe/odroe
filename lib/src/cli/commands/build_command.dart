import 'dart:isolate';

import 'package:odroe/config.dart';

import '../odroe_command.dart';
import '../utils/generate_external_command.dart';

class BuildCommand extends OdroeCommand {
  @override
  String get description => 'Build your Odroe application.';

  @override
  String get name => 'build';

  @override
  get defaultMode => OdroeMode.production;

  @override
  run() async {
    await super.run();
    await generateExtrenalCommand(
      context,
      name: 'build',
      commandPath: context.buildCommandPath,
    );

    final port = ReceivePort();
    port.listen((_) => port.close());
    await Isolate.spawnUri(Uri.file(context.buildCommandPath), [], null,
        onExit: port.sendPort);
  }
}
