import 'dart:async';

import 'package:spry/spry.dart';

/// Odroe server options
abstract class ServerOptions {
  /// Specify which IP addresses the server should listen on.
  ///
  /// Defaults to `localhost`
  String host = 'localhost';

  /// Specify server port.
  ///
  /// Defaults to 3000
  int port = 3000;

  /// Setup Spry application.
  FutureOr<void> Function(Spry app)? setup;
}
