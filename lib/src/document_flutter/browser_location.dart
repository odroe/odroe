import 'package:flutter_web_plugins/url_strategy.dart' as web_navigation;

/// Reads the route selected by Flutter's active URL strategy.
Uri? readFlutterBrowserLocation() {
  final path = web_navigation.urlStrategy?.getPath();
  return path == null ? null : Uri.tryParse(path);
}
