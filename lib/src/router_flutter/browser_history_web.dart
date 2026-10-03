import 'package:flutter_web_plugins/url_strategy.dart';

/// Whether the host exposes browser URL history.
bool get browserHistoryEnabled => urlStrategy != null;

/// Traverses the host's selected URL strategy without changing that strategy.
Future<void> moveBrowserHistory(int delta) => urlStrategy!.go(delta);
