import 'dart:isolate';

import '../odroe_command.dart';
import '../utils/generate_external_command.dart';

class DevCommand extends OdroeCommand {
  @override
  String get description => 'Starts a development Odroe application.';

  @override
  String get name => 'dev';

  @override
  run() async {
    await super.run();
    await generateExtrenalCommand(
      context,
      name: 'dev',
      commandPath: context.devCommandPath,
    );

    final port = ReceivePort();
    port.listen((_) => port.close());
    await Isolate.spawnUri(Uri.file(context.devCommandPath), [], null,
        onExit: port.sendPort);
  }
}
