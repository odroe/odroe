import 'dart:isolate';

import 'package:odroe/config.dart';

import '../odroe_command.dart';
import '../utils/generate_external_command.dart';

class GenCommand extends OdroeCommand {
  @override
  String get description => 'Generate your Odroe application.';

  @override
  String get name => 'gen';

  @override
  get defaultMode => OdroeMode.development;

  @override
  run() async {
    await super.run();
    await generateExtrenalCommand(
      context,
      name: 'generate',
      commandPath: context.genCommandPath,
    );

    final port = ReceivePort();
    port.listen((_) => port.close());
    await Isolate.spawnUri(Uri.file(context.genCommandPath), [], null,
        onExit: port.sendPort);
  }
}
