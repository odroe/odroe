import 'dart:io';

import 'package:path/path.dart' as path;

import '../context.dart';

Future<void> generateExtrenalCommand(Context context,
    {required String commandPath, required String name}) async {
  final file = File(commandPath);
  final config = path
      .relative(context.configPath, from: path.dirname(file.path))
      .replaceAll('\\', '/');
  final code = '''
import 'package:odroe/bundler.dart';
import '$config';

main(List<String> args) async => ExternalCommand.$name(await config, args);
''';

  if (!(await file.exists())) {
    await file.create(recursive: true);
  }

  await file.writeAsString(code);
}
