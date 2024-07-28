import 'env_options.dart';
import 'server_options.dart';
import 'shared_options.dart';

abstract class OdroeConfig extends SharedOptions {
  /// Environment variable configuration.
  EnvOptions get env;

  /// Server options
  ServerOptions get server;
}
