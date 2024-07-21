import 'dart:io';

import 'package:odroe/config.dart';
import 'package:path/path.dart' as path;

import '../context.dart';

Future<void> generateCachedConfigFile(
  Context context, {
  required String configFile,
  required OdroeMode mode,
}) async {
  final file = File(switch (path.isAbsolute(configFile)) {
    true => configFile,
    _ => path.join(context.root, configFile),
  });

  if (!(await file.exists())) {
    final error =
        OSError('Not fond Odroe config file ($configFile) in ${context.root}');
    throw PathNotFoundException(file.path, error);
  }

  await _validateConfigFile(file);

  final cacheConfigFile = File(context.configPath);
  final config = path
      .relative(file.path, from: path.dirname(cacheConfigFile.path))
      .replaceAll('\\', '/');
  final code = '''
import 'dart:async';
import 'dart:io';
import 'package:odroe/config.dart';
import '$config';

final FutureOr<OdroeConfig> config = extend(defineOdroeConfigOf(
  root: Directory(r'${context.root}'),
  mode: OdroeMode.${mode.name},
));
''';

  if (!(await cacheConfigFile.exists())) {
    await cacheConfigFile.create(recursive: true);
  }

  await cacheConfigFile.writeAsString(code);
}

Future<void> _validateConfigFile(File file) async {
  final regex = RegExp(
    r'(OdroeConfig|Future(Or)?\<OdroeConfug\>) extend\((OdroeConfig \w+)\)',
    caseSensitive: true,
  );
  final code = await file.readAsString();
  if (regex.hasMatch(code)) return;

  throw Exception('''
The Odroe configuration file is illegal.

path: ${file.path}

Please declare the 'extend' function correctly in the configuration file, for example:

```dart
import 'package:odroe/config.dart';

OdroeConfig extend(OdroeConfig config) {
  // ...
  return config;
}
```
  ''');
}
