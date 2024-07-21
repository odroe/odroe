import 'dart:io';

import 'env_options.dart';
import 'shared_options.dart';

abstract class OdroeConfig extends SharedOptions {
  EnvOptions? _envOptions;

  /// Environment variable configuration.
  EnvOptions get env => _envOptions ??= _EnvOptionsImpl(dir: root);
}

class _EnvOptionsImpl extends EnvOptions {
  _EnvOptionsImpl({required this.dir});

  @override
  Directory dir;
}
