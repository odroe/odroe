import 'dart:io';

import 'package:odroe/src/cli/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runOdroe(arguments);
}
