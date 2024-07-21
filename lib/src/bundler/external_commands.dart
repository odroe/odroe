import 'package:odroe/config.dart';

extension type ExternalCommand._(Object _) {
  static build(OdroeConfig config, List<String> args) {
    print('Build.');
  }

  static dev(OdroeConfig config, List<String> args) {
    print('Dev.');
  }
}
